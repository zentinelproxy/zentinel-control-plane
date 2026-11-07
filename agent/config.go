package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config is read from ZCP_* environment variables.
type Config struct {
	URL               string
	Project           string
	RegistrationToken string
	NodeName          string
	Labels            map[string]string
	StateDir          string
	ConfigDir         string
	Reload            string
	ValidateCmd       string
	PublicKey         ed25519.PublicKey
	RequireSignature  bool
	Interval          time.Duration
	ProxyVersion      string
}

func loadConfig(getenv func(string) string) (*Config, error) {
	c := &Config{
		URL:               strings.TrimRight(getenv("ZCP_URL"), "/"),
		Project:           getenv("ZCP_PROJECT"),
		RegistrationToken: getenv("ZCP_REGISTRATION_TOKEN"),
		NodeName:          getenv("ZCP_NODE_NAME"),
		StateDir:          valueOr(getenv("ZCP_STATE_DIR"), "/var/lib/zentinel-cp-agent"),
		ConfigDir:         valueOr(getenv("ZCP_CONFIG_DIR"), "/etc/zentinel"),
		Reload:            valueOr(getenv("ZCP_RELOAD"), "none"),
		ValidateCmd:       getenv("ZCP_VALIDATE_CMD"),
		ProxyVersion:      getenv("ZCP_PROXY_VERSION"),
		Interval:          15 * time.Second,
	}

	if c.URL == "" || c.Project == "" {
		return nil, fmt.Errorf("ZCP_URL and ZCP_PROJECT are required")
	}

	if c.NodeName == "" {
		host, err := os.Hostname()
		if err != nil {
			return nil, fmt.Errorf("ZCP_NODE_NAME is not set and the hostname is unknown: %w", err)
		}
		c.NodeName = host
	}

	labels, err := parseLabels(getenv("ZCP_LABELS"))
	if err != nil {
		return nil, err
	}
	c.Labels = labels

	if err := validateReload(c.Reload); err != nil {
		return nil, err
	}

	if v := getenv("ZCP_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d < time.Second {
			return nil, fmt.Errorf("ZCP_INTERVAL must be a duration of at least 1s, such as 15s")
		}
		c.Interval = d
	}

	if v := getenv("ZCP_PUBLIC_KEY"); v != "" {
		raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(v))
		if err != nil || len(raw) != ed25519.PublicKeySize {
			return nil, fmt.Errorf("ZCP_PUBLIC_KEY must be a Base64 Ed25519 public key")
		}
		c.PublicKey = ed25519.PublicKey(raw)
	}

	if v := getenv("ZCP_REQUIRE_SIGNATURE"); v != "" {
		required, err := strconv.ParseBool(v)
		if err != nil {
			return nil, fmt.Errorf("ZCP_REQUIRE_SIGNATURE must be true or false")
		}
		c.RequireSignature = required
	}

	if c.RequireSignature && c.PublicKey == nil {
		return nil, fmt.Errorf("ZCP_REQUIRE_SIGNATURE needs ZCP_PUBLIC_KEY")
	}

	return c, nil
}

func valueOr(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

// parseLabels reads "key=value,key=value".
func parseLabels(s string) (map[string]string, error) {
	labels := map[string]string{}
	for _, pair := range strings.Split(s, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		key, value, ok := strings.Cut(pair, "=")
		if !ok || strings.TrimSpace(key) == "" {
			return nil, fmt.Errorf("ZCP_LABELS entry %q is not key=value", pair)
		}
		labels[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return labels, nil
}

// validateReload checks the reload method:
//
//	none            the proxy watches its config (auto-reload)
//	pid:<n>         send SIGHUP to process n
//	pidfile:<path>  send SIGHUP to the process in the file
//	command:<cmd>   run a shell command
func validateReload(r string) error {
	switch {
	case r == "none":
		return nil
	case strings.HasPrefix(r, "pid:"):
		if _, err := strconv.Atoi(strings.TrimPrefix(r, "pid:")); err != nil {
			return fmt.Errorf("ZCP_RELOAD pid:<n> needs a number")
		}
		return nil
	case strings.HasPrefix(r, "pidfile:") && len(r) > len("pidfile:"):
		return nil
	case strings.HasPrefix(r, "command:") && len(r) > len("command:"):
		return nil
	}
	return fmt.Errorf("ZCP_RELOAD must be none, pid:<n>, pidfile:<path> or command:<cmd>")
}
