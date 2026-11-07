package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// applyBundle validates the bundle, writes it to the config directory and
// reloads the proxy. If writing or reloading fails, the previous files are
// restored. Returns the paths written, for removing stale files next time.
func applyBundle(cfg *Config, files map[string][]byte, previous []string) ([]string, error) {
	if err := validate(cfg, files); err != nil {
		return nil, fmt.Errorf("validation failed: %w", err)
	}

	backup, err := snapshot(cfg.ConfigDir, previous, files)
	if err != nil {
		return nil, fmt.Errorf("backing up current config: %w", err)
	}

	written, err := writeFiles(cfg.ConfigDir, files)
	if err == nil {
		removeStale(cfg.ConfigDir, previous, files)
		err = reload(cfg.Reload)
	}
	if err != nil {
		if restoreErr := restore(cfg.ConfigDir, backup, files); restoreErr != nil {
			return nil, fmt.Errorf("%v; restoring the previous config also failed: %v", err, restoreErr)
		}
		if previous != nil {
			_ = reload(cfg.Reload)
		}
		return nil, err
	}
	return written, nil
}

// validate runs ZCP_VALIDATE_CMD on a copy of the bundle, with {config} replaced
// by the path of its zentinel.kdl.
func validate(cfg *Config, files map[string][]byte) error {
	if cfg.ValidateCmd == "" {
		return nil
	}
	dir, err := os.MkdirTemp("", "zentinel-bundle-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dir)

	if _, err := writeFiles(dir, files); err != nil {
		return err
	}
	command := strings.ReplaceAll(cfg.ValidateCmd, "{config}", filepath.Join(dir, "zentinel.kdl"))
	out, err := exec.Command("/bin/sh", "-c", command).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// writeFiles writes each file atomically. zentinel.kdl goes last, so a proxy
// watching it sees the new config only when everything it references exists.
func writeFiles(dir string, files map[string][]byte) ([]string, error) {
	names := make([]string, 0, len(files))
	for name := range files {
		if name != "zentinel.kdl" {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	names = append(names, "zentinel.kdl")

	for _, name := range names {
		target := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return nil, err
		}
		if err := writeFileAtomic(target, files[name], 0o644); err != nil {
			return nil, err
		}
	}
	return names, nil
}

type backupEntry struct {
	existed bool
	data    []byte
	mode    os.FileMode
}

func snapshot(dir string, previous []string, files map[string][]byte) (map[string]backupEntry, error) {
	backup := map[string]backupEntry{}
	names := append([]string{}, previous...)
	for name := range files {
		names = append(names, name)
	}
	for _, name := range names {
		target := filepath.Join(dir, filepath.FromSlash(name))
		info, err := os.Stat(target)
		if os.IsNotExist(err) {
			backup[name] = backupEntry{}
			continue
		}
		if err != nil {
			return nil, err
		}
		data, err := os.ReadFile(target)
		if err != nil {
			return nil, err
		}
		backup[name] = backupEntry{existed: true, data: data, mode: info.Mode().Perm()}
	}
	return backup, nil
}

func restore(dir string, backup map[string]backupEntry, files map[string][]byte) error {
	for name, entry := range backup {
		target := filepath.Join(dir, filepath.FromSlash(name))
		if entry.existed {
			if err := writeFileAtomic(target, entry.data, entry.mode); err != nil {
				return err
			}
		} else if _, written := files[name]; written {
			if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
	}
	return nil
}

// removeStale deletes files the previous bundle wrote that the new one lacks.
func removeStale(dir string, previous []string, files map[string][]byte) {
	for _, name := range previous {
		if _, kept := files[name]; !kept {
			_ = os.Remove(filepath.Join(dir, filepath.FromSlash(name)))
		}
	}
}

func reload(method string) error {
	switch {
	case method == "none":
		return nil
	case strings.HasPrefix(method, "process:"):
		pids, err := findProcesses("/proc", strings.TrimPrefix(method, "process:"))
		if err != nil {
			return err
		}
		for _, pid := range pids {
			if err := syscall.Kill(pid, syscall.SIGHUP); err != nil {
				return fmt.Errorf("signalling process %d: %w", pid, err)
			}
		}
		return nil
	case strings.HasPrefix(method, "pid:"):
		pid, _ := strconv.Atoi(strings.TrimPrefix(method, "pid:"))
		return syscall.Kill(pid, syscall.SIGHUP)
	case strings.HasPrefix(method, "pidfile:"):
		data, err := os.ReadFile(strings.TrimPrefix(method, "pidfile:"))
		if err != nil {
			return fmt.Errorf("reading pid file: %w", err)
		}
		pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err != nil {
			return fmt.Errorf("pid file does not hold a number")
		}
		return syscall.Kill(pid, syscall.SIGHUP)
	case strings.HasPrefix(method, "command:"):
		cmd := exec.Command("/bin/sh", "-c", strings.TrimPrefix(method, "command:"))
		done := make(chan error, 1)
		var out []byte
		go func() {
			var err error
			out, err = cmd.CombinedOutput()
			done <- err
		}()
		select {
		case err := <-done:
			if err != nil {
				return fmt.Errorf("reload command failed: %v: %s", err, strings.TrimSpace(string(out)))
			}
			return nil
		case <-time.After(2 * time.Minute):
			_ = cmd.Process.Kill()
			return fmt.Errorf("reload command timed out")
		}
	}
	return fmt.Errorf("unknown reload method %q", method)
}

// findProcesses returns the IDs of processes named name, read from a
// /proc-style directory. With the proxy sharing the agent's process namespace,
// this finds it without a pid file.
func findProcesses(procDir, name string) ([]int, error) {
	entries, err := os.ReadDir(procDir)
	if err != nil {
		return nil, fmt.Errorf("listing processes: %w", err)
	}
	var pids []int
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid == os.Getpid() {
			continue
		}
		comm, err := os.ReadFile(filepath.Join(procDir, e.Name(), "comm"))
		if err == nil && strings.TrimSpace(string(comm)) == name {
			pids = append(pids, pid)
		}
	}
	if len(pids) == 0 {
		return nil, fmt.Errorf("no running process named %q", name)
	}
	return pids, nil
}
