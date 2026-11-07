package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/klauspost/compress/zstd"
)

type entry struct {
	name     string
	body     string
	typeflag byte
}

func makeTar(t *testing.T, entries []entry) []byte {
	t.Helper()
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	for _, e := range entries {
		flag := e.typeflag
		if flag == 0 {
			flag = tar.TypeReg
		}
		hdr := &tar.Header{Name: e.name, Mode: 0o644, Size: int64(len(e.body)), Typeflag: flag}
		if flag == tar.TypeSymlink {
			hdr.Size, hdr.Linkname = 0, "/etc/passwd"
		}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if flag == tar.TypeReg {
			if _, err := tw.Write([]byte(e.body)); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func sha(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func gzipped(t *testing.T, b []byte) []byte {
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	w.Write(b)
	w.Close()
	return buf.Bytes()
}

func zstded(t *testing.T, b []byte) []byte {
	enc, err := zstd.NewWriter(nil)
	if err != nil {
		t.Fatal(err)
	}
	return enc.EncodeAll(b, nil)
}

func bundleWith(t *testing.T, kdl string, extra map[string]string) []byte {
	files := []map[string]any{{"path": "zentinel.kdl", "checksum": sha([]byte(kdl))}}
	entries := []entry{{name: "zentinel.kdl", body: kdl}}
	for name, body := range extra {
		files = append(files, map[string]any{"path": name, "checksum": sha([]byte(body))})
		entries = append(entries, entry{name: name, body: body})
	}
	manifest, _ := json.Marshal(map[string]any{"files": files})
	entries = append(entries, entry{name: "manifest.json", body: string(manifest)})
	return zstded(t, makeTar(t, entries))
}

func TestExtractsZstdGzipAndPlainTar(t *testing.T) {
	plain := makeTar(t, []entry{{name: "zentinel.kdl", body: "a"}, {name: "certs/x.pem", body: "b"}})
	for name, archive := range map[string][]byte{"zstd": zstded(t, plain), "gzip": gzipped(t, plain), "tar": plain} {
		files, err := extractBundle(archive)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if string(files["zentinel.kdl"]) != "a" || string(files["certs/x.pem"]) != "b" {
			t.Fatalf("%s: wrong contents %v", name, files)
		}
	}
}

func TestRejectsUnsafeArchives(t *testing.T) {
	cases := map[string][]entry{
		"parent path":   {{name: "zentinel.kdl", body: "a"}, {name: "../evil", body: "x"}},
		"nested parent": {{name: "zentinel.kdl", body: "a"}, {name: "certs/../../evil", body: "x"}},
		"absolute":      {{name: "zentinel.kdl", body: "a"}, {name: "/etc/evil", body: "x"}},
		"symlink":       {{name: "zentinel.kdl", body: "a"}, {name: "link", typeflag: tar.TypeSymlink}},
		"no config":     {{name: "other.kdl", body: "a"}},
	}
	for name, entries := range cases {
		if _, err := extractBundle(makeTar(t, entries)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}

func TestRejectsManifestMismatch(t *testing.T) {
	manifest := `{"files":[{"path":"zentinel.kdl","checksum":"` + sha([]byte("other")) + `"}]}`
	archive := makeTar(t, []entry{{name: "zentinel.kdl", body: "a"}, {name: "manifest.json", body: manifest}})
	if _, err := extractBundle(archive); err == nil || !strings.Contains(err.Error(), "checksum") {
		t.Fatalf("expected checksum error, got %v", err)
	}
}

func TestVerifiesChecksumAndSignature(t *testing.T) {
	pub, priv, _ := ed25519.GenerateKey(rand.Reader)
	otherPub, _, _ := ed25519.GenerateKey(rand.Reader)
	archive := []byte("archive")
	sig := base64.StdEncoding.EncodeToString(ed25519.Sign(priv, archive))

	if err := verifyBundle(archive, sha(archive), sig, pub, true); err != nil {
		t.Fatalf("valid bundle rejected: %v", err)
	}
	if err := verifyBundle(archive, sha([]byte("x")), sig, pub, false); err == nil {
		t.Error("wrong checksum accepted")
	}
	if err := verifyBundle(archive, sha(archive), sig, otherPub, false); err == nil {
		t.Error("signature from another key accepted")
	}
	if err := verifyBundle(archive, sha(archive), "", pub, true); err == nil {
		t.Error("unsigned bundle accepted when signatures are required")
	}
	if err := verifyBundle(archive, sha(archive), "", nil, false); err != nil {
		t.Errorf("unsigned bundle rejected when signatures are optional: %v", err)
	}
}

func TestConfig(t *testing.T) {
	env := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
	base := map[string]string{"ZCP_URL": "https://cp.example.com/", "ZCP_PROJECT": "p", "ZCP_NODE_NAME": "n"}

	cfg, err := loadConfig(env(base))
	if err != nil || cfg.URL != "https://cp.example.com" || cfg.Reload != "none" {
		t.Fatalf("defaults: %+v %v", cfg, err)
	}

	bad := map[string]map[string]string{
		"missing url":  {"ZCP_PROJECT": "p"},
		"bad reload":   {"ZCP_RELOAD": "kill"},
		"bad labels":   {"ZCP_LABELS": "novalue"},
		"bad key":      {"ZCP_PUBLIC_KEY": "short"},
		"sig, no key":  {"ZCP_REQUIRE_SIGNATURE": "true"},
		"bad interval": {"ZCP_INTERVAL": "10ms"},
	}
	for name, extra := range bad {
		m := map[string]string{}
		for k, v := range base {
			m[k] = v
		}
		if name == "missing url" {
			delete(m, "ZCP_URL")
		}
		for k, v := range extra {
			m[k] = v
		}
		if _, err := loadConfig(env(m)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}

	m := map[string]string{"ZCP_LABELS": "env=prod, region = eu"}
	for k, v := range base {
		m[k] = v
	}
	cfg, _ = loadConfig(env(m))
	if cfg.Labels["env"] != "prod" || cfg.Labels["region"] != "eu" {
		t.Errorf("labels: %v", cfg.Labels)
	}
}

func TestApplyWritesRemovesStaleAndRollsBack(t *testing.T) {
	dir := t.TempDir()
	cfg := &Config{ConfigDir: dir, Reload: "none"}

	written, err := applyBundle(cfg, map[string][]byte{"zentinel.kdl": []byte("v1"), "old.pem": []byte("o")}, nil)
	if err != nil {
		t.Fatal(err)
	}

	written, err = applyBundle(cfg, map[string][]byte{"zentinel.kdl": []byte("v2")}, written)
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "zentinel.kdl")); string(got) != "v2" {
		t.Fatalf("config not updated: %q", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "old.pem")); !os.IsNotExist(err) {
		t.Error("file from the previous bundle was not removed")
	}

	cfg.Reload = "command:exit 3"
	if _, err := applyBundle(cfg, map[string][]byte{"zentinel.kdl": []byte("v3"), "new.pem": []byte("n")}, written); err == nil {
		t.Fatal("failed reload reported as success")
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "zentinel.kdl")); string(got) != "v2" {
		t.Errorf("config not restored after a failed reload: %q", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "new.pem")); !os.IsNotExist(err) {
		t.Error("file added by the failed bundle was left behind")
	}
}

func TestValidationFailureLeavesConfigAlone(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "zentinel.kdl"), []byte("current"), 0o644)
	cfg := &Config{ConfigDir: dir, Reload: "none", ValidateCmd: "grep -q valid {config}"}

	if _, err := applyBundle(cfg, map[string][]byte{"zentinel.kdl": []byte("broken")}, []string{"zentinel.kdl"}); err == nil {
		t.Fatal("invalid config accepted")
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "zentinel.kdl")); string(got) != "current" {
		t.Errorf("config changed by a bundle that failed validation: %q", got)
	}
	if _, err := applyBundle(cfg, map[string][]byte{"zentinel.kdl": []byte("valid")}, nil); err != nil {
		t.Errorf("valid config rejected: %v", err)
	}
}

// fakeCP implements the node API endpoints the agent uses.
type fakeCP struct {
	mu         sync.Mutex
	archive    []byte
	bundleID   string
	active     []string
	events     []string
	registered int
	keys       map[string]bool
}

func (f *fakeCP) handler(t *testing.T) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/projects/demo/nodes/register", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Registration-Token") != "token" {
			w.WriteHeader(401)
			return
		}
		f.mu.Lock()
		f.registered++
		key := "key" + string(rune('0'+f.registered))
		f.keys[key] = true
		f.mu.Unlock()
		w.WriteHeader(201)
		json.NewEncoder(w).Encode(map[string]string{"node_id": "node-1", "node_key": key})
	})
	auth := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			f.mu.Lock()
			ok := f.keys[r.Header.Get("X-Zentinel-Node-Key")]
			f.mu.Unlock()
			if !ok {
				w.WriteHeader(401)
				return
			}
			next(w, r)
		}
	}
	mux.HandleFunc("POST /api/v1/nodes/node-1/heartbeat", auth(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		f.mu.Lock()
		if id, _ := body["active_bundle_id"].(string); id != "" {
			f.active = append(f.active, id)
		}
		f.mu.Unlock()
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}))
	mux.HandleFunc("GET /api/v1/nodes/node-1/bundles/latest", auth(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.bundleID == "" {
			json.NewEncoder(w).Encode(map[string]any{"no_update": true})
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"bundle_id": f.bundleID, "version": "1.0.0", "checksum": sha(f.archive),
			"download_path": "/api/v1/nodes/node-1/bundles/" + f.bundleID + "/download",
		})
	}))
	mux.HandleFunc("GET /api/v1/nodes/node-1/bundles/{id}/download", auth(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		w.Write(f.archive)
	}))
	mux.HandleFunc("POST /api/v1/nodes/node-1/events", auth(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		// The control plane accepts only these types.
		switch body["event_type"] {
		case "config_reload", "bundle_switch", "error", "startup", "shutdown", "warning", "info":
		default:
			w.WriteHeader(422)
			return
		}
		f.mu.Lock()
		f.events = append(f.events, body["event_type"].(string))
		f.mu.Unlock()
		w.WriteHeader(201)
	}))
	return mux
}

func TestSyncRegistersInstallsAndReports(t *testing.T) {
	cp := &fakeCP{keys: map[string]bool{}}
	srv := httptest.NewServer(cp.handler(t))
	defer srv.Close()

	stateDir, configDir := t.TempDir(), t.TempDir()
	cfg := &Config{
		URL: srv.URL, Project: "demo", RegistrationToken: "token", NodeName: "n1",
		StateDir: stateDir, ConfigDir: configDir, Reload: "none",
	}
	agent, err := newAgent(cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}

	if err := agent.sync(); err != nil {
		t.Fatalf("first sync: %v", err)
	}
	if cp.registered != 1 {
		t.Fatalf("registered %d times", cp.registered)
	}

	cp.archive = bundleWith(t, "system {}", map[string]string{"certs/a.pem": "pem"})
	cp.bundleID = "bundle-1"
	if err := agent.sync(); err != nil {
		t.Fatalf("sync with bundle: %v", err)
	}
	if got, _ := os.ReadFile(filepath.Join(configDir, "zentinel.kdl")); string(got) != "system {}" {
		t.Fatalf("config not installed: %q", got)
	}
	if got, _ := os.ReadFile(filepath.Join(configDir, "certs/a.pem")); string(got) != "pem" {
		t.Fatalf("extra file not installed: %q", got)
	}
	if len(cp.active) == 0 || cp.active[len(cp.active)-1] != "bundle-1" {
		t.Errorf("active bundle not reported: %v", cp.active)
	}
	if len(cp.events) != 1 || cp.events[0] != "bundle_switch" {
		t.Errorf("events: %v", cp.events)
	}

	// A restarted agent keeps its identity and its active bundle.
	agent2, _ := newAgent(cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := agent2.sync(); err != nil {
		t.Fatal(err)
	}
	if cp.registered != 1 || agent2.state.ActiveBundleID != "bundle-1" {
		t.Errorf("state lost on restart: registered=%d active=%q", cp.registered, agent2.state.ActiveBundleID)
	}
	if info, _ := os.Stat(statePath(stateDir)); info.Mode().Perm() != 0o600 {
		t.Errorf("state file mode %v", info.Mode().Perm())
	}

	// A rejected key leads to a new registration.
	cp.mu.Lock()
	cp.keys = map[string]bool{}
	cp.mu.Unlock()
	if err := agent2.sync(); err != nil {
		t.Fatalf("sync after key rejection: %v", err)
	}
	if cp.registered != 2 {
		t.Errorf("did not register again, registered=%d", cp.registered)
	}
}

func TestSyncReportsABadBundle(t *testing.T) {
	cp := &fakeCP{keys: map[string]bool{}}
	srv := httptest.NewServer(cp.handler(t))
	defer srv.Close()

	cfg := &Config{URL: srv.URL, Project: "demo", RegistrationToken: "token", NodeName: "n1",
		StateDir: t.TempDir(), ConfigDir: t.TempDir(), Reload: "none"}
	agent, _ := newAgent(cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))

	cp.archive = makeTar(t, []entry{{name: "zentinel.kdl", body: "a"}, {name: "../escape", body: "x"}})
	cp.bundleID = "bad"
	if err := agent.sync(); err == nil {
		t.Fatal("bad bundle installed")
	}
	if len(cp.events) != 1 || cp.events[0] != "error" {
		t.Errorf("events: %v", cp.events)
	}
	if agent.state.ActiveBundleID != "" {
		t.Error("bad bundle recorded as active")
	}
}

func TestFindProcesses(t *testing.T) {
	proc := t.TempDir()
	for pid, comm := range map[string]string{"1": "zentinel\n", "17": "sh\n", "42": "zentinel\n", "self": "x"} {
		os.MkdirAll(filepath.Join(proc, pid), 0o755)
		os.WriteFile(filepath.Join(proc, pid, "comm"), []byte(comm), 0o644)
	}
	pids, err := findProcesses(proc, "zentinel")
	if err != nil || len(pids) != 2 {
		t.Fatalf("got %v %v", pids, err)
	}
	if pids, err := findProcesses(proc, "nginx"); err != nil || len(pids) != 0 {
		t.Errorf("missing process: got %v %v", pids, err)
	}
}
