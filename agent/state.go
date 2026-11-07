package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

// State is what the agent keeps between runs.
type State struct {
	NodeID         string   `json:"node_id"`
	NodeKey        string   `json:"node_key"`
	ActiveBundleID string   `json:"active_bundle_id,omitempty"`
	ActiveFiles    []string `json:"active_files,omitempty"`
}

func statePath(dir string) string { return filepath.Join(dir, "state.json") }

func loadState(dir string) (*State, error) {
	data, err := os.ReadFile(statePath(dir))
	if errors.Is(err, os.ErrNotExist) {
		return &State{}, nil
	}
	if err != nil {
		return nil, err
	}
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// save writes the state atomically. It holds the node key, so only the agent
// can read it.
func (s *State) save(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(statePath(dir), data, 0o600)
}

// writeFileAtomic writes to a temporary file in the same directory and renames
// it over the target, so readers never see a partial file.
func writeFileAtomic(path string, data []byte, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
