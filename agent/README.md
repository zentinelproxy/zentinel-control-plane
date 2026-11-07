# zentinel-cp-agent

Connects a stock [Zentinel proxy](https://github.com/zentinelproxy/zentinel) to
the Zentinel control plane. The proxy has no control-plane client of its own,
so the agent runs next to it and:

1. registers the proxy as a node, using the project's registration token,
2. sends heartbeats, reporting the bundle it runs,
3. downloads each bundle rolled out to it, checks its checksum, signature and
   file manifest, and validates the config with `zentinel test`,
4. installs the files atomically and reloads the proxy,
5. puts the previous config back if installing or reloading fails, and reports
   the result as a node event.

Rollouts advance when the heartbeat reports the new bundle as active.

## Running with Docker

[`docker-compose.example.yml`](docker-compose.example.yml) runs the agent and a
stock proxy. The proxy shares the agent's process namespace so the agent can
signal it, and starts once the first config is installed.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `ZCP_URL` | required | Control plane URL, such as `https://cp.example.com` |
| `ZCP_PROJECT` | required | Project slug |
| `ZCP_REGISTRATION_TOKEN` | | Project registration token, needed for the first registration |
| `ZCP_NODE_NAME` | hostname | Node name, unique within the project |
| `ZCP_LABELS` | | `key=value,key=value`, for targeting rollouts |
| `ZCP_CONFIG_DIR` | `/etc/zentinel` | Where bundle files are installed. The proxy reads `zentinel.kdl` from here |
| `ZCP_STATE_DIR` | `/var/lib/zentinel-cp-agent` | Node ID, node key and active bundle. Keep it private and persistent |
| `ZCP_RELOAD` | `none` | `process:<name>`, `pid:<n>`, `pidfile:<path>`, `command:<cmd>`, or `none` when the proxy uses `auto-reload` |
| `ZCP_VALIDATE_CMD` | | Command run before installing, with `{config}` replaced by the new `zentinel.kdl` |
| `ZCP_PUBLIC_KEY` | | Base64 Ed25519 public key; when set, signed bundles must verify |
| `ZCP_REQUIRE_SIGNATURE` | `false` | Refuse unsigned bundles |
| `ZCP_INTERVAL` | `15s` | Time between syncs |
| `ZCP_PROXY_VERSION` | | Proxy version reported to the control plane |

The image sets `ZCP_VALIDATE_CMD` to `zentinel test -c {config}` and
`ZCP_RELOAD` to `process:zentinel`.

After the first registration the agent authenticates with its node key, kept
in the state directory. If the control plane rejects that key, for example
because the node was deleted, the agent registers again with the token.

## Building

```bash
go test ./...
go build -o zentinel-cp-agent .
```
