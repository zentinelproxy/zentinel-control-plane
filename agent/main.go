// Command zentinel-cp-agent connects a stock Zentinel proxy to the Zentinel
// control plane. It runs next to the proxy, registers it as a node, sends
// heartbeats, and installs the bundles the control plane rolls out to it.
//
// Configuration is read from ZCP_* environment variables; see README.md.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"
)

var version = "dev"

func main() {
	once := flag.Bool("once", false, "run one sync and exit")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	cfg, err := loadConfig(os.Getenv)
	if err != nil {
		log.Error("invalid configuration", "error", err)
		os.Exit(2)
	}

	agent, err := newAgent(cfg, log)
	if err != nil {
		log.Error("cannot start", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if *once {
		if err := agent.sync(); err != nil {
			log.Error("sync failed", "error", err)
			os.Exit(1)
		}
		return
	}
	agent.run(ctx)
}

type Agent struct {
	cfg    *Config
	log    *slog.Logger
	client *Client
	state  *State
}

func newAgent(cfg *Config, log *slog.Logger) (*Agent, error) {
	state, err := loadState(cfg.StateDir)
	if err != nil {
		return nil, fmt.Errorf("reading state: %w", err)
	}
	if err := os.MkdirAll(cfg.ConfigDir, 0o755); err != nil {
		return nil, fmt.Errorf("creating config directory: %w", err)
	}
	client := newClient(cfg.URL)
	client.nodeKey = state.NodeKey
	return &Agent{cfg: cfg, log: log, client: client, state: state}, nil
}

func (a *Agent) run(ctx context.Context) {
	wait := time.Duration(0)
	for {
		select {
		case <-ctx.Done():
			a.log.Info("stopping")
			return
		case <-time.After(wait):
		}

		wait = a.cfg.Interval
		if err := a.sync(); err != nil {
			a.log.Warn("sync failed", "error", err)
		}
	}
}

// sync registers if needed, sends a heartbeat, and installs a new bundle if one
// is staged for this node.
func (a *Agent) sync() error {
	if err := a.ensureRegistered(); err != nil {
		return err
	}

	err := a.heartbeat()
	if errors.Is(err, errUnauthorized) {
		// The node was deleted or its key replaced: register again.
		a.log.Warn("node credentials rejected, registering again")
		a.state.NodeID, a.state.NodeKey = "", ""
		if err := a.ensureRegistered(); err != nil {
			return err
		}
		err = a.heartbeat()
	}
	if err != nil {
		return fmt.Errorf("heartbeat: %w", err)
	}

	latest, err := a.client.latest(a.state.NodeID)
	if err != nil {
		return fmt.Errorf("checking for a bundle: %w", err)
	}
	if latest.NoUpdate || latest.BundleID == "" || latest.BundleID == a.state.ActiveBundleID {
		return nil
	}

	if err := a.install(latest); err != nil {
		a.log.Error("bundle not installed", "bundle_id", latest.BundleID, "error", err)
		_ = a.client.event(a.state.NodeID, "bundle_apply_failed", "error", err.Error(),
			map[string]any{"bundle_id": latest.BundleID, "version": latest.Version})
		return err
	}

	a.log.Info("bundle installed", "bundle_id", latest.BundleID, "version", latest.Version)
	_ = a.client.event(a.state.NodeID, "bundle_applied", "info", "Bundle "+latest.Version+" installed",
		map[string]any{"bundle_id": latest.BundleID, "version": latest.Version})
	return a.heartbeat()
}

func (a *Agent) ensureRegistered() error {
	if a.state.NodeID != "" && a.state.NodeKey != "" {
		a.client.nodeKey = a.state.NodeKey
		return nil
	}
	host, _ := os.Hostname()
	resp, err := a.client.register(a.cfg.Project, a.cfg.RegistrationToken, map[string]any{
		"name":         a.cfg.NodeName,
		"labels":       a.cfg.Labels,
		"version":      a.cfg.ProxyVersion,
		"hostname":     host,
		"capabilities": []string{},
		"metadata":     map[string]any{"agent": "zentinel-cp-agent", "agent_version": version},
	})
	if err != nil {
		return fmt.Errorf("registering: %w", err)
	}
	a.state.NodeID, a.state.NodeKey = resp.NodeID, resp.NodeKey
	a.client.nodeKey = resp.NodeKey
	if err := a.state.save(a.cfg.StateDir); err != nil {
		return fmt.Errorf("saving state: %w", err)
	}
	a.log.Info("registered", "node_id", resp.NodeID, "name", a.cfg.NodeName)
	return nil
}

func (a *Agent) heartbeat() error {
	host, _ := os.Hostname()
	body := map[string]any{
		"version":  a.cfg.ProxyVersion,
		"hostname": host,
		"health":   map[string]any{"status": "healthy"},
		"metadata": map[string]any{"agent_version": version, "os": runtime.GOOS},
	}
	if a.state.ActiveBundleID != "" {
		body["active_bundle_id"] = a.state.ActiveBundleID
	}
	return a.client.heartbeat(a.state.NodeID, body)
}

func (a *Agent) install(latest *LatestResponse) error {
	if latest.DownloadPath == "" {
		return fmt.Errorf("the control plane gave no download path")
	}
	archive, err := a.client.download(latest.DownloadPath)
	if err != nil {
		return fmt.Errorf("downloading: %w", err)
	}
	if err := verifyBundle(archive, latest.Checksum, latest.Signature, a.cfg.PublicKey, a.cfg.RequireSignature); err != nil {
		return err
	}
	files, err := extractBundle(archive)
	if err != nil {
		return err
	}
	written, err := applyBundle(a.cfg, files, a.state.ActiveFiles)
	if err != nil {
		return err
	}
	a.state.ActiveBundleID = latest.BundleID
	a.state.ActiveFiles = written
	return a.state.save(a.cfg.StateDir)
}
