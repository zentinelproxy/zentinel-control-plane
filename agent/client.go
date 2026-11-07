package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// maxBundleBytes caps a download, so a misbehaving server cannot fill the disk.
const maxBundleBytes = 256 << 20

var errUnauthorized = errors.New("node credentials were rejected")

type Client struct {
	base    string
	http    *http.Client
	nodeKey string
}

func newClient(base string) *Client {
	return &Client{base: base, http: &http.Client{Timeout: 60 * time.Second}}
}

type RegisterResponse struct {
	NodeID  string `json:"node_id"`
	NodeKey string `json:"node_key"`
}

type LatestResponse struct {
	NoUpdate     bool   `json:"no_update"`
	BundleID     string `json:"bundle_id"`
	Version      string `json:"version"`
	Checksum     string `json:"checksum"`
	DownloadPath string `json:"download_path"`
	Signature    string `json:"signature"`
	PollAfterS   int    `json:"poll_after_s"`
}

func (c *Client) register(project, token string, body map[string]any) (*RegisterResponse, error) {
	headers := map[string]string{}
	if token != "" {
		headers["X-Registration-Token"] = token
	}
	var out RegisterResponse
	if err := c.doJSON("POST", "/api/v1/projects/"+project+"/nodes/register", headers, body, &out, http.StatusCreated); err != nil {
		return nil, err
	}
	if out.NodeID == "" || out.NodeKey == "" {
		return nil, fmt.Errorf("registration response has no node ID or key")
	}
	return &out, nil
}

func (c *Client) heartbeat(nodeID string, body map[string]any) error {
	return c.doJSON("POST", "/api/v1/nodes/"+nodeID+"/heartbeat", c.authHeaders(), body, nil, http.StatusOK)
}

func (c *Client) latest(nodeID string) (*LatestResponse, error) {
	var out LatestResponse
	if err := c.doJSON("GET", "/api/v1/nodes/"+nodeID+"/bundles/latest", c.authHeaders(), nil, &out, http.StatusOK); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) event(nodeID, eventType, severity, message string, metadata map[string]any) error {
	body := map[string]any{"event_type": eventType, "severity": severity, "message": message, "metadata": metadata}
	return c.doJSON("POST", "/api/v1/nodes/"+nodeID+"/events", c.authHeaders(), body, nil, http.StatusCreated)
}

func (c *Client) download(path string) ([]byte, error) {
	req, err := http.NewRequest("GET", c.base+path, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range c.authHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized {
		return nil, errUnauthorized
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxBundleBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxBundleBytes {
		return nil, fmt.Errorf("bundle is larger than %d bytes", maxBundleBytes)
	}
	return data, nil
}

func (c *Client) authHeaders() map[string]string {
	return map[string]string{"X-Zentinel-Node-Key": c.nodeKey}
}

func (c *Client) doJSON(method, path string, headers map[string]string, body any, out any, want int) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequest(method, c.base+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode == http.StatusUnauthorized {
		return fmt.Errorf("%w: %s", errUnauthorized, string(data))
	}
	if resp.StatusCode != want {
		return fmt.Errorf("%s %s: HTTP %d: %s", method, path, resp.StatusCode, string(data))
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}
