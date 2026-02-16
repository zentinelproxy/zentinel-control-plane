# Node Management

This guide covers the full lifecycle of Sentinel proxy nodes: registration, authentication, heartbeats, groups, labels, drift detection, version pinning, and decommissioning.

## Node Registration

Nodes register with the control plane to receive configuration bundles.

### Registration API

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/nodes/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "proxy-us-east-1",
    "labels": {"region": "us-east-1", "env": "production"},
    "version": "1.5.0",
    "capabilities": ["http2", "grpc"]
  }'
```

**Response** (201 Created):
```json
{
  "node_id": "uuid",
  "node_key": "base64-encoded-32-byte-key",
  "poll_interval_s": 5
}
```

**Important**: The `node_key` is returned **only once** during registration. Store it securely on the node. The control plane stores only the SHA256 hash of the key.

### Registration Properties

| Property | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Unique name within the project |
| `labels` | No | Key-value metadata for targeting |
| `capabilities` | No | Feature flags (e.g., `["http2", "grpc"]`) |
| `version` | No | Sentinel software version |

## Authentication

Nodes authenticate with the control plane using one of two methods.

### Static Key (Simple)

Send the node key in every request via the `X-Sentinel-Node-Key` header:

```
X-Sentinel-Node-Key: base64-encoded-node-key
```

The control plane hashes the key and looks up the node. This method is simple but means the key is sent with every request.

### JWT Token (Recommended)

Exchange the static key for a short-lived JWT token:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/:node_id/token \
  -H "X-Sentinel-Node-Key: base64-encoded-node-key"
```

**Response**:
```json
{
  "token": "eyJ...",
  "expires_at": "2026-02-17T05:00:00Z"
}
```

Then use the JWT in subsequent requests:

```
Authorization: Bearer eyJ...
```

JWT tokens:
- Are signed with Ed25519 (EdDSA) using the org's signing keys
- Expire after 12 hours (default)
- Contain `sub` (node ID), `prj` (project ID), `org` (org ID), and `kid` (key ID)
- Can be verified without database lookups using the public key

The node's `auth_method` is updated to `jwt` when a token is issued.

See [Security > Signing Keys](security.md#signing-keys-jwt) for key management.

## Heartbeats

Nodes send periodic heartbeats to report their status and metrics.

### Heartbeat API

```bash
curl -X POST http://localhost:4000/api/v1/nodes/:node_id/heartbeat \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "1.5.0",
    "ip": "10.0.1.42",
    "hostname": "proxy-us-east-1.internal",
    "health": {
      "cpu_percent": 45,
      "memory_percent": 62,
      "uptime_seconds": 86400
    },
    "metrics": {
      "requests_total": 150000,
      "errors_total": 42,
      "latency_p99_ms": 85
    },
    "active_bundle_id": "current-bundle-uuid",
    "staged_bundle_id": "next-bundle-uuid"
  }'
```

### What Heartbeats Update

Each heartbeat:
- Sets the node's `status` to `online`
- Updates `last_seen_at` to the current timestamp
- Records the node's `version`, `ip`, `hostname`, `capabilities`, and `metadata`
- Stores a `NodeHeartbeat` history record with health and metrics
- Updates `active_bundle_id` and `staged_bundle_id`
- Processes circuit breaker statuses (if reported)

### Heartbeat History

The last 1,000 heartbeats are retained per node (older ones are pruned). You can query recent heartbeats for a node:

```
GET /api/v1/projects/:slug/nodes/:id  (includes recent heartbeats)
```

### Staleness Detection

The `StalenessWorker` runs periodically and marks nodes as `offline` when:

- `last_seen_at` is more than **120 seconds** ago (default threshold)
- The node was previously `online`

This is a global sweep, not per-node. The threshold can be configured.

## Node Status

| Status | Meaning |
|--------|---------|
| `online` | Healthy — recent heartbeat received |
| `offline` | No heartbeat for >120 seconds |
| `unknown` | Initial state before first heartbeat |

Query node statistics for a project:

```bash
curl http://localhost:4000/api/v1/projects/my-project/nodes/stats \
  -H "Authorization: Bearer API_KEY"
```

Returns counts by status: `{total, online, offline, unknown}`.

## Labels

Labels are key-value metadata attached to nodes for filtering and targeting.

### Setting Labels

Labels are set during registration or updated afterward:

```json
{
  "labels": {
    "region": "us-east-1",
    "env": "production",
    "tier": "edge",
    "datacenter": "dc1"
  }
}
```

### Filtering by Labels

List nodes matching specific labels:

```bash
curl "http://localhost:4000/api/v1/projects/my-project/nodes?labels[region]=us-east-1" \
  -H "Authorization: Bearer API_KEY"
```

### Using Labels in Rollouts

Target nodes by labels in rollout selectors:

```json
{
  "target_selector": {
    "type": "labels",
    "labels": {"env": "production", "region": "us-east-1"}
  }
}
```

## Node Groups

Node groups organize nodes into named collections for easier management and targeting.

### Managing Groups

| Operation | Description |
|-----------|-------------|
| Create group | Name and optional description, assigned a color |
| Add nodes | Add individual nodes to a group |
| Remove nodes | Remove individual nodes from a group |
| Set members | Replace group membership atomically |
| Delete group | Remove the group (does not delete nodes) |

### Using Groups in Rollouts

Target node groups in rollout selectors:

```json
{
  "target_selector": {
    "type": "groups",
    "group_ids": ["canary-group-uuid", "edge-group-uuid"]
  }
}
```

Groups can overlap — a node can belong to multiple groups. When multiple groups are specified, the union of all nodes is targeted.

## Environment Assignment

Nodes can be assigned to an [environment](core-concepts.md#environments) (dev, staging, production):

- **Assign**: Link a node to an environment
- **Batch assign**: Assign multiple nodes at once
- **Remove**: Unlink a node from its environment

Environment assignment enables environment-scoped rollouts and per-environment observability.

## Drift Detection

Configuration drift occurs when a node's active bundle doesn't match its expected bundle.

### How Drift Is Detected

1. When a rollout completes, each target node's `expected_bundle_id` is set to the deployed bundle
2. The `DriftWorker` runs every 30 seconds (configurable via `drift_check_interval`)
3. For each online node, it compares `active_bundle_id` vs `expected_bundle_id`
4. If they differ, a `DriftEvent` is created

### Drift Events

| Property | Description |
|----------|-------------|
| `expected_bundle_id` | What the node should be running |
| `actual_bundle_id` | What the node is actually running |
| `severity` | Based on change count: critical (>50), high (>20), medium (>5), low (≤5) |
| `detected_at` | When drift was first detected |
| `resolved_at` | When drift was resolved (if resolved) |
| `resolution` | How it was resolved: `auto_corrected`, `manual`, `rollout_started`, `rollout_completed` |
| `diff_stats` | Change statistics: additions, deletions, unchanged |

### Drift Statistics

Query drift statistics for a project:
- `total_managed`: Nodes with an expected bundle
- `drifted`: Nodes where active ≠ expected
- `in_sync`: Nodes where active = expected
- `active_events`: Unresolved drift events
- `resolved_today`: Events resolved in the last 24 hours

### Auto-Remediation

When `drift_auto_remediation` is enabled on a project:

1. Drift is detected for a node
2. The control plane automatically creates a rollout targeting just that node
3. The rollout deploys the expected bundle
4. The drift event is resolved with `resolution: "rollout_started"`

### Alert Thresholds

Configure project-level drift alert thresholds:

- `drift_alert_threshold`: Percentage of nodes (e.g., 10 = alert when >10% are drifted)
- `drift_alert_node_count`: Absolute count (e.g., 5 = alert when >5 nodes are drifted)

When exceeded, a `drift.threshold_exceeded` event is emitted for notification routing.

## Version Pinning

Pin a node to a specific bundle version to prevent rollouts from changing its configuration:

```
pin_node_to_bundle(node, bundle)
```

Pinned nodes are automatically excluded from rollouts unless the rollout deploys their pinned bundle. This is useful for:

- Nodes running a custom configuration for testing
- Nodes that need a specific version for compatibility
- Gradual opt-out from fleet-wide deployments

Unpin a node to return it to normal rollout participation:

```
unpin_node(node)
```

### Version Constraints

Set minimum and/or maximum bundle version constraints on a node:

```
set_node_version_constraints(node, %{min_bundle_version: "1.2.0", max_bundle_version: "2.0.0"})
```

The control plane checks `bundle_satisfies_constraints?` to verify that a bundle's version falls within the node's constraints before including it in a rollout.

## Runtime Configuration

Nodes can push their current KDL runtime configuration to the control plane:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/:node_id/config \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"config_kdl": "route \"/api\" { ... }"}'
```

The configuration is stored with a SHA256 hash for change detection. This enables:

- Viewing the actual running configuration of any node
- Comparing running config vs expected config for drift analysis

## Node Events

Nodes can report operational events to the control plane:

```bash
curl -X POST http://localhost:4000/api/v1/nodes/:node_id/events \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {"event_type": "bundle_switch", "severity": "info", "message": "Switched to bundle abc123"},
      {"event_type": "error", "severity": "error", "message": "Upstream connection failed"}
    ]
  }'
```

### Event Types

| Type | Description |
|------|-------------|
| `config_reload` | Configuration was reloaded |
| `bundle_switch` | Active bundle changed |
| `error` | An error occurred |
| `startup` | Node started |
| `shutdown` | Node shutting down |
| `warning` | Non-critical warning |
| `info` | Informational message |

The last 500 events are retained per node.

## Decommissioning

Remove a node from the fleet:

```bash
curl -X DELETE http://localhost:4000/api/v1/projects/my-project/nodes/:id \
  -H "Authorization: Bearer API_KEY"
```

This permanently deletes the node and its associated data (heartbeats, events, group memberships). The node's key becomes invalid immediately.
