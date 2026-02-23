# Proxy Registration

End-to-end guide for connecting existing zentinel proxy instances to the control plane.

## Prerequisites

- Control plane running and accessible (see [DEPLOYMENT.md](DEPLOYMENT.md))
- An organization and project created in the control plane (see [GETTING-STARTED.md](GETTING-STARTED.md))
- The `zentinel` proxy binary installed on target machines
- `curl` or equivalent HTTP client for API calls

## 1. Register the Proxy

Register a node with the control plane via the REST API. No authentication is required for registration — only the project slug.

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/nodes/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "proxy-us-east-1",
    "labels": {"env": "production", "region": "us-east-1"},
    "version": "1.0.0",
    "ip": "10.0.1.50",
    "hostname": "proxy-us-east-1.internal"
  }'
```

### Request Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique name within the project (1-100 chars, alphanumeric + `_` `.` `-`) |
| `labels` | No | Key-value metadata for targeting rollouts |
| `version` | No | Proxy version string |
| `ip` | No | Node IP address (auto-detected from request if omitted) |
| `hostname` | No | Node hostname |
| `capabilities` | No | Feature capabilities array |
| `metadata` | No | Additional JSON metadata |

### Response

```json
{
  "node_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "node_key": "sk_abc123def456...",
  "poll_interval_s": 30
}
```

**Important:** The `node_key` is returned only once. Store it securely — it cannot be retrieved again.

## 2. Configure the Proxy

Configure the zentinel proxy to communicate with the control plane using the credentials from registration. Set these values in the proxy's configuration:

| Setting | Value |
|---------|-------|
| `control_plane_url` | URL of the control plane (e.g., `http://localhost:4000`) |
| `node_id` | The `node_id` from the registration response |
| `node_key` | The `node_key` from the registration response |

The proxy uses these to authenticate heartbeats, bundle polling, and event reporting.

## 3. Verify Connection

Once the proxy is configured and started, it will begin sending heartbeats to the control plane. Verify the connection:

**Check via the dashboard:** Navigate to your project in the web UI — the node should appear with status "online".

**Check via the API:**

```bash
curl http://localhost:4000/api/v1/projects/my-project/nodes \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Look for your node with `"status": "online"` and a recent `last_seen_at` timestamp.

### Heartbeat Details

The proxy sends heartbeats to `POST /api/v1/nodes/:node_id/heartbeat` at the interval specified by `poll_interval_s` (default: 30 seconds). Each heartbeat can include:

```json
{
  "health": {"cpu_percent": 12.5, "memory_percent": 45.0},
  "metrics": {"requests_per_second": 1500},
  "active_bundle_id": "bundle-uuid-if-running",
  "version": "1.0.0"
}
```

Nodes that stop sending heartbeats for 120 seconds are marked as "offline" by the staleness worker.

## 4. Upgrade to JWT Authentication (Recommended)

The static `node_key` from registration works for authentication but JWT tokens are recommended for production. JWTs are short-lived (12-hour TTL) and signed with Ed25519 keys.

### Prerequisites

Your organization needs an active signing key. Create one in the web UI under **Organization > Signing Keys**, or it will be created automatically on first token request.

### Exchange Key for Token

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/token \
  -H "X-Zentinel-Node-Key: sk_abc123def456..."
```

Response:

```json
{
  "token": "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCIsImtpZCI6InNrXy4uLiJ9...",
  "token_type": "Bearer",
  "expires_at": "2026-02-24T06:30:00Z",
  "expires_in": 43200
}
```

### Use the JWT

Once you have a token, use it in the `Authorization` header instead of `X-Zentinel-Node-Key`:

```bash
# Heartbeat with JWT
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/heartbeat \
  -H "Authorization: Bearer eyJhbGciOi..." \
  -H "Content-Type: application/json" \
  -d '{"health": {"cpu_percent": 10}}'
```

The proxy should automatically refresh the token before expiry by calling the token endpoint again.

### Authentication Methods

The control plane accepts either method on all node endpoints:

| Method | Header | Use Case |
|--------|--------|----------|
| Static key | `X-Zentinel-Node-Key: sk_...` | Initial setup, simple deployments |
| JWT Bearer | `Authorization: Bearer eyJ...` | Production (recommended) |

## 5. Deploy a Bundle

With a node registered and connected, you can deploy configuration bundles:

1. **Compile a bundle** — Create a bundle via the web UI (Bundles > New Bundle) or the API. The control plane validates the KDL configuration using the `zentinel` binary and packages it as a `.tar.zst` archive.

2. **Create a rollout** — Create a rollout targeting your node(s). Choose a strategy (rolling, canary, blue-green, or all-at-once) and configure health gates.

3. **Node pulls the bundle** — The proxy polls `GET /api/v1/nodes/:node_id/bundles/latest` at its configured interval. When a rollout assigns a new bundle, the response includes a presigned download URL:

```json
{
  "bundle_id": "bundle-uuid",
  "version": "v1.2.3",
  "checksum": "sha256:abc123...",
  "size_bytes": 51200,
  "download_url": "https://s3.../bundle.tar.zst?X-Amz-...",
  "poll_after_s": 30
}
```

When no update is pending:

```json
{
  "no_update": true,
  "poll_after_s": 30
}
```

4. **Node reports status** — After applying the bundle, the proxy reports `active_bundle_id` in its next heartbeat. The rollout engine uses this to track progress and evaluate health gates.

## 6. Reporting Events and Metrics

Registered proxies can send operational data back to the control plane:

### Events

Valid event types: `config_reload`, `bundle_switch`, `error`, `startup`, `shutdown`, `warning`, `info`.
Valid severities: `debug`, `info`, `warn`, `error`.

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/events \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "startup",
    "severity": "info",
    "message": "Proxy started successfully"
  }'
```

Batch events:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/events \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {"event_type": "bundle_switch", "severity": "info", "message": "Switched to bundle v1.2.3"},
      {"event_type": "info", "severity": "info", "message": "All upstreams healthy"}
    ]
  }'
```

### Metrics

Service-level metrics require `service_id` and `project_id`. These are structured metric snapshots, not free-form key-value pairs:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/metrics \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "metrics": [{
      "service_id": "SERVICE_UUID",
      "project_id": "PROJECT_UUID",
      "period_start": "2026-02-23T10:00:00Z",
      "period_seconds": 60,
      "request_count": 1500,
      "error_count": 3,
      "status_2xx": 1450,
      "status_4xx": 47,
      "status_5xx": 3
    }],
    "request_logs": [{
      "service_id": "SERVICE_UUID",
      "project_id": "PROJECT_UUID",
      "timestamp": "2026-02-23T10:00:00Z",
      "method": "GET",
      "path": "/api/health",
      "status": 200,
      "latency_ms": 5
    }]
  }'
```

### WAF Events

WAF events require `rule_type`, `rule_id`, `action`, and `severity`:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/waf-events \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "rule_type": "crs",
      "rule_id": "942100",
      "action": "blocked",
      "severity": "warn",
      "client_ip": "1.2.3.4",
      "method": "POST",
      "path": "/login",
      "timestamp": "2026-02-23T10:00:00Z",
      "matched_data": "1 OR 1=1",
      "metadata": {"category": "sql_injection"}
    }]
  }'
```

### Runtime Config

```bash
curl -X POST http://localhost:4000/api/v1/nodes/NODE_ID/config \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"config_kdl": "route \"/api/*\" { upstream \"http://api:8080\" }"}'
```

## 7. Bulk Registration

Register multiple nodes with a shell script:

```bash
#!/bin/bash
set -euo pipefail

CP_URL="http://localhost:4000"
PROJECT="my-project"

NODES=(
  "proxy-us-east-1:us-east-1:10.0.1.50"
  "proxy-us-west-2:us-west-2:10.0.2.50"
  "proxy-eu-west-1:eu-west-1:10.1.1.50"
  "proxy-ap-south-1:ap-south-1:10.2.1.50"
)

for entry in "${NODES[@]}"; do
  IFS=":" read -r name region ip <<< "$entry"

  echo "Registering $name..."
  response=$(curl -s -X POST "$CP_URL/api/v1/projects/$PROJECT/nodes/register" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"labels\": {\"env\": \"production\", \"region\": \"$region\"},
      \"ip\": \"$ip\"
    }")

  node_id=$(echo "$response" | jq -r '.node_id')
  node_key=$(echo "$response" | jq -r '.node_key')

  echo "  node_id: $node_id"
  echo "  node_key: $node_key"

  # Store credentials (adapt to your secrets management)
  echo "$name,$node_id,$node_key" >> node-credentials.csv
done

echo "Done. Credentials saved to node-credentials.csv"
```

**Important:** Protect `node-credentials.csv` — it contains authentication keys that cannot be retrieved again.

## 8. Troubleshooting

### Node Shows as "Offline"

- **Check heartbeats**: Nodes are marked offline after 120 seconds without a heartbeat. Verify the proxy is running and can reach the control plane.
- **Check network**: Ensure the proxy can reach `POST /api/v1/nodes/:node_id/heartbeat` on the control plane host and port.
- **Check credentials**: Verify the `node_id` and `node_key` match the registration response.

### Authentication Failures (401)

| Error Message | Cause | Fix |
|---------------|-------|-----|
| "Missing authentication..." | No auth header sent | Add `X-Zentinel-Node-Key` or `Authorization: Bearer` header |
| "Invalid node key" | Wrong or corrupted static key | Re-register the node to get a new key |
| "Invalid token signature" | JWT signed with wrong key | Re-issue token via `POST /nodes/:id/token` |
| "Token expired" | JWT past 12-hour TTL | Request a new token |
| "Signing key has been deactivated" | Org key was deactivated | Create a new signing key and re-issue tokens |
| "Node not found" | Node was deleted | Re-register the node |

### Bundle Not Pulling

- **No rollout active**: Bundles are only assigned to nodes through rollouts. Create a rollout targeting the node.
- **Rollout paused/failed**: Check rollout status in the dashboard. Health gate failures pause rollouts automatically.
- **Wrong labels**: If the rollout uses label-based targeting, verify the node's labels match the target selector.
- **Poll interval**: The node may not have polled yet. Default interval is 30 seconds.

### Registration Fails (422)

- **Duplicate name**: Node names must be unique within a project. Choose a different name or delete the existing node.
- **Invalid name format**: Names must be 1-100 characters, start with alphanumeric, and contain only alphanumeric characters, underscores, dots, and hyphens.
- **Project not found (404)**: Verify the project slug in the URL matches an existing project.

## Node API Reference

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/v1/projects/:slug/nodes/register` | POST | None | Register a new node |
| `/api/v1/nodes/:id/heartbeat` | POST | Node | Send heartbeat |
| `/api/v1/nodes/:id/bundles/latest` | GET | Node | Poll for bundle updates |
| `/api/v1/nodes/:id/token` | POST | Node | Exchange key for JWT |
| `/api/v1/nodes/:id/events` | POST | Node | Report events |
| `/api/v1/nodes/:id/config` | POST | Node | Report runtime config |
| `/api/v1/nodes/:id/metrics` | POST | Node | Upload metrics and request logs |
| `/api/v1/nodes/:id/waf-events` | POST | Node | Report WAF events |

"Node" auth means either `X-Zentinel-Node-Key` or `Authorization: Bearer <jwt>`.

See [API.md](API.md) for the full REST API reference.
