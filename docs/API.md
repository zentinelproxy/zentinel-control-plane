# API Reference

Base URL: `/api/v1`

## Authentication

| Consumer | Method | Header |
|----------|--------|--------|
| Operator / CI | API key | `Authorization: Bearer <api_key>` |
| Node (simple) | Static key | `X-Zentinel-Node-Key: <key>` |
| Node (recommended) | JWT | `Authorization: Bearer <jwt>` |
| Webhooks | HMAC signature | Provider-specific headers |

See [AUTHENTICATION.md](AUTHENTICATION.md) for details on scopes and key management.

## Operator API

All endpoints under `/api/v1/projects/:project_slug/`. Require API key authentication.

### Bundles

#### Create Bundle

```
POST /api/v1/projects/:project_slug/bundles
Scope: bundles:write
```

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/bundles \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "config_source": "route \"/api/*\" {\n  upstream \"http://api:8080\"\n}",
    "version": "1.0.0"
  }'
```

Response (201): Bundle object with `status: "compiling"`. Poll until `status: "compiled"`.

#### List Bundles

```
GET /api/v1/projects/:project_slug/bundles?status=compiled
Scope: bundles:read
```

#### Get Bundle

```
GET /api/v1/projects/:project_slug/bundles/:id
Scope: bundles:read
```

Returns full bundle object with metadata, risk score, and SBOM.

#### Download Bundle

```
GET /api/v1/projects/:project_slug/bundles/:id/download
Scope: bundles:read
```

Returns presigned S3 URL for the `.tar.zst` archive.

#### Assign Bundle to Nodes

```
POST /api/v1/projects/:project_slug/bundles/:id/assign
Scope: bundles:write
```

```json
{"node_ids": ["node-uuid-1", "node-uuid-2"]}
```

Sets `staged_bundle_id` on specified nodes.

#### Revoke Bundle

```
POST /api/v1/projects/:project_slug/bundles/:id/revoke
Scope: bundles:write
```

Prevents further distribution.

#### Verify Signature

```
GET /api/v1/projects/:project_slug/bundles/:id/verify
Scope: bundles:read
```

#### Get SBOM

```
GET /api/v1/projects/:project_slug/bundles/:id/sbom
Scope: bundles:read
```

Returns CycloneDX 1.5 JSON.

### Rollouts

#### Create Rollout

```
POST /api/v1/projects/:project_slug/rollouts
Scope: rollouts:write
```

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/rollouts \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "bundle_id": "BUNDLE_UUID",
    "strategy": "rolling",
    "batch_size": 2,
    "target_selector": {"type": "all"},
    "health_gates": {
      "heartbeat_healthy": true,
      "max_error_rate": 5.0,
      "max_latency_ms": 500
    },
    "progress_deadline_seconds": 600,
    "auto_rollback": true
  }'
```

Optional fields: `environment_id`, `scheduled_at` (ISO 8601).

Response (201): Rollout with `state: "pending"`.

#### List Rollouts

```
GET /api/v1/projects/:project_slug/rollouts?state=running
Scope: rollouts:read
```

States: `pending`, `running`, `paused`, `completed`, `cancelled`, `failed`.

#### Get Rollout

```
GET /api/v1/projects/:project_slug/rollouts/:id
Scope: rollouts:read
```

Returns rollout with steps, node bundle statuses, and progress.

#### Control Rollout

```
POST /api/v1/projects/:project_slug/rollouts/:id/pause
POST /api/v1/projects/:project_slug/rollouts/:id/resume
POST /api/v1/projects/:project_slug/rollouts/:id/cancel
POST /api/v1/projects/:project_slug/rollouts/:id/rollback
Scope: rollouts:write
```

#### Blue-Green / Canary Controls

```
POST /api/v1/projects/:project_slug/rollouts/:id/swap-slot
POST /api/v1/projects/:project_slug/rollouts/:id/advance-traffic
Scope: rollouts:write
```

### Nodes

#### List Nodes

```
GET /api/v1/projects/:project_slug/nodes?status=online&labels[region]=us-east-1
Scope: nodes:read
```

#### Get Node

```
GET /api/v1/projects/:project_slug/nodes/:id
Scope: nodes:read
```

#### Node Statistics

```
GET /api/v1/projects/:project_slug/nodes/stats
Scope: nodes:read
```

```json
{"total": 50, "online": 45, "offline": 3, "unknown": 2}
```

#### Delete Node

```
DELETE /api/v1/projects/:project_slug/nodes/:id
Scope: nodes:write
```

### Services

```
GET    /projects/:slug/services              # List (services:read)
POST   /projects/:slug/services              # Create (services:write)
GET    /projects/:slug/services/:id          # Get (services:read)
PUT    /projects/:slug/services/:id          # Update (services:write)
DELETE /projects/:slug/services/:id          # Delete (services:write)
PUT    /projects/:slug/services/reorder      # Batch reorder (services:write)
POST   /projects/:slug/services/generate-bundle  # KDL generation (services:write)
```

### Upstream Groups

```
GET    /projects/:slug/upstream-groups           # List
POST   /projects/:slug/upstream-groups           # Create
PUT    /projects/:slug/upstream-groups/:id       # Update
DELETE /projects/:slug/upstream-groups/:id       # Delete
POST   /projects/:slug/upstream-groups/:id/targets        # Add target
PUT    /upstream-groups/:id/targets/:target_id             # Update target
DELETE /upstream-groups/:id/targets/:target_id             # Remove target
```

### Certificates

```
GET    /projects/:slug/certificates              # List
POST   /projects/:slug/certificates              # Upload/create
GET    /projects/:slug/certificates/:id/download # Download PEM
DELETE /projects/:slug/certificates/:id          # Delete
```

### Additional Resources

Standard CRUD under `/api/v1/projects/:project_slug/`:

| Resource | Path | Read Scope | Write Scope |
|----------|------|------------|-------------|
| Auth Policies | `auth-policies` | `services:read` | `services:write` |
| Middlewares | `middlewares` | `services:read` | `services:write` |
| Plugins | `plugins` | `services:read` | `services:write` |
| Secrets | `secrets` | `services:read` | `services:write` |
| Trust Stores | `trust-stores` | `services:read` | `services:write` |
| Internal CA | `internal-ca` | `services:read` | `services:write` |
| Service Templates | `service-templates` | `services:read` | `services:write` |
| OpenAPI Specs | `openapi` | `services:read` | `services:write` |

### Drift

```
GET  /projects/:slug/drift                    # List events (nodes:read)
GET  /projects/:slug/drift/stats              # Statistics (nodes:read)
GET  /projects/:slug/drift/:id                # Event details (nodes:read)
POST /projects/:slug/drift/:id/resolve        # Resolve (nodes:write)
POST /projects/:slug/drift/resolve-all        # Batch resolve (nodes:write)
GET  /projects/:slug/drift/export             # Export CSV (nodes:read)
```

### Config Management

```
GET  /projects/:slug/config/export            # Export project config (services:read)
POST /projects/:slug/config/import            # Import config (services:write)
POST /projects/:slug/config/diff              # Compare configs (services:read)
```

### API Keys

```
GET    /api/v1/api-keys                       # List (api_keys:admin)
POST   /api/v1/api-keys                       # Create (api_keys:admin)
GET    /api/v1/api-keys/:id                   # Show (api_keys:admin)
POST   /api/v1/api-keys/:id/revoke            # Revoke (api_keys:admin)
DELETE /api/v1/api-keys/:id                   # Delete (api_keys:admin)
```

Raw key returned only on creation.

### Audit

```
GET  /api/v1/audit/verify                     # Verify chain integrity
GET  /api/v1/audit/checkpoints                # List checkpoints
POST /api/v1/audit/checkpoints                # Create checkpoint
```

## Node API

Endpoints used by Zentinel proxy instances.

### Register Node

```
POST /api/v1/projects/:project_slug/nodes/register
Auth: None (public endpoint)
```

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/nodes/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "proxy-us-east-1",
    "labels": {"region": "us-east-1", "env": "production"},
    "version": "1.5.0",
    "capabilities": ["http2"]
  }'
```

Response (201):
```json
{
  "node_id": "uuid",
  "node_key": "base64-url-key",
  "poll_interval_s": 5
}
```

**Store `node_key` securely** — returned only once.

### Heartbeat

```
POST /api/v1/nodes/:node_id/heartbeat
Auth: Node key or JWT
```

```json
{
  "version": "1.5.0",
  "ip": "10.0.1.42",
  "hostname": "proxy-us-east-1",
  "health": {"cpu_percent": 45, "memory_percent": 62},
  "metrics": {"requests_total": 150000},
  "active_bundle_id": "uuid",
  "staged_bundle_id": "uuid"
}
```

### Poll for Bundle

```
GET /api/v1/nodes/:node_id/bundles/latest
Auth: Node key or JWT
```

Returns bundle metadata + presigned S3 download URL, or **204** if no update.

### Exchange Key for JWT

```
POST /api/v1/nodes/:node_id/token
Auth: X-Zentinel-Node-Key header
```

```json
{"token": "eyJ...", "expires_at": "2026-02-21T19:00:00Z"}
```

### Report Events

```
POST /api/v1/nodes/:node_id/events
Auth: Node key or JWT
```

```json
{
  "events": [
    {"event_type": "bundle_switch", "severity": "info", "message": "Activated bundle abc123"}
  ]
}
```

### Push Runtime Config

```
POST /api/v1/nodes/:node_id/config
Auth: Node key or JWT
```

```json
{"config_kdl": "route \"/api\" { upstream \"http://backend:8080\" }"}
```

### Push Metrics

```
POST /api/v1/nodes/:node_id/metrics
Auth: Node key or JWT
```

```json
{
  "metrics": [{
    "service_id": "uuid",
    "period_start": "2026-02-16T12:00:00Z",
    "request_count": 1500,
    "error_count": 3,
    "latency_p99_ms": 85,
    "status_2xx": 1450,
    "status_5xx": 3
  }],
  "request_logs": [{
    "service_id": "uuid",
    "timestamp": "2026-02-16T12:01:00Z",
    "method": "GET",
    "path": "/api/users",
    "status": 200,
    "latency_ms": 45
  }]
}
```

### Push WAF Events

```
POST /api/v1/nodes/:node_id/waf-events
Auth: Node key or JWT
```

```json
{
  "events": [{
    "service_id": "uuid",
    "rule_type": "sqli",
    "rule_id": "CRS-942100",
    "action": "blocked",
    "severity": "critical",
    "client_ip": "192.168.1.100",
    "method": "POST",
    "path": "/api/login",
    "matched_data": "' OR 1=1 --"
  }]
}
```

## Webhook API

GitOps triggers with HMAC signature verification:

```
POST /api/v1/webhooks/github       # GitHub push events
POST /api/v1/webhooks/gitlab       # GitLab push events
POST /api/v1/webhooks/bitbucket    # Bitbucket push events
POST /api/v1/webhooks/gitea        # Gitea push events
POST /api/v1/webhooks/generic      # Custom HMAC webhook
```

Push to the configured branch triggers automatic bundle compilation.

## GraphQL API

```
POST /api/v1/graphql
Auth: Authorization: Bearer <api_key>
```

Full query/mutation/subscription access via Absinthe. Subscriptions available for real-time updates (alert state changes, rollout progress).

GraphiQL IDE available at `/dev/graphiql` (development only).

## Health Endpoints

```
GET /health     # Liveness check (no auth)
GET /ready      # Readiness check (no auth)
GET /metrics    # Prometheus metrics (no auth)
GET /api/docs   # Interactive API docs (Scalar)
```

## Error Responses

```json
{
  "error": "Short error description",
  "details": "Optional detailed message"
}
```

Validation errors:
```json
{"errors": {"email": ["has already been taken"]}}
```

### Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (e.g., no bundle update) |
| 400 | Bad Request — malformed input |
| 401 | Unauthorized — missing or invalid credentials |
| 403 | Forbidden — insufficient scope |
| 404 | Not Found |
| 409 | Conflict — duplicate resource |
| 422 | Unprocessable Entity — validation failure |
| 429 | Too Many Requests — rate limited |
| 500 | Internal Server Error |

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1708099200
```

429 responses include `retry_after` (seconds).
