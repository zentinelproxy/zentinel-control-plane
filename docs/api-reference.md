# API Reference

This document covers the Zentinel Control Plane REST API, Node API, and GraphQL endpoint.

## Authentication

### API Key Authentication

Operator and CI/CD requests authenticate with API keys:

```
Authorization: Bearer YOUR_API_KEY
```

API keys are created via the UI or API. See [Security > API Key Management](security.md#api-key-management) for details on scopes and lifecycle.

### Node Authentication

Zentinel proxy nodes authenticate using one of two methods:

**Static key** (simple):
```
X-Zentinel-Node-Key: base64-encoded-key
```

**JWT token** (recommended):
```
Authorization: Bearer eyJ...
```

See [Node Management > Authentication](node-management.md#authentication) for details.

### Scope Enforcement

API keys can have scopes that restrict access to specific endpoint categories:

| Scope | Endpoints |
|-------|-----------|
| `nodes:read` | List nodes, view node details, node stats |
| `nodes:write` | Register nodes, delete nodes, drift operations |
| `bundles:read` | List bundles, view bundle details, download, verify, SBOM |
| `bundles:write` | Create bundles, assign to nodes, revoke |
| `rollouts:read` | List rollouts, view rollout details |
| `rollouts:write` | Create, pause, resume, cancel, rollback rollouts |
| `services:read` | List services, upstream groups, certificates, etc. |
| `services:write` | Create/update/delete services and related resources |
| `api_keys:admin` | Create, list, revoke, delete API keys |

API keys with empty scopes have full access (backward compatibility).

## Operator REST API

All operator endpoints are under `/api/v1/projects/:project_slug/` and require API key authentication.

### Bundles

#### Create Bundle

```
POST /api/v1/projects/:project_slug/bundles
Scope: bundles:write
```

**Request body**:
```json
{
  "config_source": "route \"/api/*\" {\n  upstream \"http://api.internal:8080\"\n}",
  "version": "1.0.0"
}
```

**Response** (201): Bundle object with `status: "compiling"`. Compilation runs asynchronously.

#### List Bundles

```
GET /api/v1/projects/:project_slug/bundles
Scope: bundles:read
```

**Query parameters**:
- `status`: Filter by status (`compiling`, `compiled`, `revoked`)

**Response** (200): Array of bundle objects.

#### Get Bundle

```
GET /api/v1/projects/:project_slug/bundles/:id
Scope: bundles:read
```

**Response** (200): Full bundle object with metadata, risk score, and SBOM.

#### Download Bundle

```
GET /api/v1/projects/:project_slug/bundles/:id/download
Scope: bundles:read
```

**Response** (200): Presigned S3 URL for downloading the `.tar.zst` archive.

#### Assign Bundle to Nodes

```
POST /api/v1/projects/:project_slug/bundles/:id/assign
Scope: bundles:write
```

**Request body**:
```json
{
  "node_ids": ["node-uuid-1", "node-uuid-2"]
}
```

Sets `staged_bundle_id` on the specified nodes.

#### Revoke Bundle

```
POST /api/v1/projects/:project_slug/bundles/:id/revoke
Scope: bundles:write
```

Prevents the bundle from being distributed to any more nodes.

#### Verify Bundle Signature

```
GET /api/v1/projects/:project_slug/bundles/:id/verify
Scope: bundles:read
```

**Response** (200): Signature verification result (valid/invalid, key used).

#### Get Bundle SBOM

```
GET /api/v1/projects/:project_slug/bundles/:id/sbom
Scope: bundles:read
```

**Response** (200): CycloneDX 1.5 JSON SBOM.

### Rollouts

#### Create Rollout

```
POST /api/v1/projects/:project_slug/rollouts
Scope: rollouts:write
```

**Request body**:
```json
{
  "bundle_id": "bundle-uuid",
  "strategy": "rolling",
  "batch_size": 2,
  "target_selector": {"type": "all"},
  "health_gates": {
    "heartbeat_healthy": true,
    "max_error_rate": 5.0
  },
  "progress_deadline_seconds": 600,
  "auto_rollback": true,
  "environment_id": "optional-env-uuid",
  "scheduled_at": "optional-iso8601-datetime"
}
```

**Response** (201): Rollout object with `state: "pending"`.

#### List Rollouts

```
GET /api/v1/projects/:project_slug/rollouts
Scope: rollouts:read
```

**Query parameters**:
- `state`: Filter by state (`pending`, `running`, `paused`, `completed`, `cancelled`, `failed`)

#### Get Rollout

```
GET /api/v1/projects/:project_slug/rollouts/:id
Scope: rollouts:read
```

**Response** (200): Rollout with steps, node bundle statuses, and progress.

#### Control Rollout

```
POST /api/v1/projects/:project_slug/rollouts/:id/pause
POST /api/v1/projects/:project_slug/rollouts/:id/resume
POST /api/v1/projects/:project_slug/rollouts/:id/cancel
POST /api/v1/projects/:project_slug/rollouts/:id/rollback
Scope: rollouts:write
```

#### Blue-Green Controls

```
POST /api/v1/projects/:project_slug/rollouts/:id/swap-slot
POST /api/v1/projects/:project_slug/rollouts/:id/advance-traffic
Scope: rollouts:write
```

### Nodes

#### List Nodes

```
GET /api/v1/projects/:project_slug/nodes
Scope: nodes:read
```

**Query parameters**:
- `status`: Filter by status (`online`, `offline`, `unknown`)
- `labels[key]`: Filter by label value

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

**Response** (200):
```json
{
  "total": 50,
  "online": 45,
  "offline": 3,
  "unknown": 2
}
```

#### Delete Node

```
DELETE /api/v1/projects/:project_slug/nodes/:id
Scope: nodes:write
```

### Services

```
GET    /api/v1/projects/:project_slug/services           # List
POST   /api/v1/projects/:project_slug/services           # Create
GET    /api/v1/projects/:project_slug/services/:id        # Show
PUT    /api/v1/projects/:project_slug/services/:id        # Update
DELETE /api/v1/projects/:project_slug/services/:id        # Delete
Scope: services:read (GET), services:write (POST/PUT/DELETE)
```

### Upstream Groups

```
GET    /api/v1/projects/:project_slug/upstream-groups
POST   /api/v1/projects/:project_slug/upstream-groups
GET    /api/v1/projects/:project_slug/upstream-groups/:id
PUT    /api/v1/projects/:project_slug/upstream-groups/:id
DELETE /api/v1/projects/:project_slug/upstream-groups/:id
Scope: services:read / services:write
```

### Certificates

```
GET    /api/v1/projects/:project_slug/certificates
POST   /api/v1/projects/:project_slug/certificates
GET    /api/v1/projects/:project_slug/certificates/:id
PUT    /api/v1/projects/:project_slug/certificates/:id
DELETE /api/v1/projects/:project_slug/certificates/:id
Scope: services:read / services:write
```

### Additional Service Resources

The following resources follow the same CRUD pattern under `/api/v1/projects/:project_slug/`:

| Resource | Endpoint Prefix |
|----------|----------------|
| Auth Policies | `auth-policies` |
| Middlewares | `middlewares` |
| Plugins | `plugins` |
| Secrets | `secrets` |
| Trust Stores | `trust-stores` |
| Internal CA | `internal-ca` |
| Service Templates | `service-templates` |
| OpenAPI Specs | `openapi` |

### Drift

```
GET  /api/v1/projects/:project_slug/drift           # List drift events
POST /api/v1/projects/:project_slug/drift/:id/resolve  # Resolve drift event
Scope: nodes:read (GET), nodes:write (POST)
```

### Configuration Management

```
GET  /api/v1/projects/:project_slug/config/export    # Export project config
POST /api/v1/projects/:project_slug/config/import    # Import config
POST /api/v1/projects/:project_slug/config/diff      # Compare configs
Scope: services:read (export), services:write (import/diff)
```

### API Keys

```
GET    /api/v1/api-keys           # List your API keys
POST   /api/v1/api-keys           # Create new API key
GET    /api/v1/api-keys/:id       # Show API key details
POST   /api/v1/api-keys/:id/revoke  # Revoke API key
DELETE /api/v1/api-keys/:id       # Delete API key
Scope: api_keys:admin
```

### Audit

```
GET  /api/v1/audit/verify        # Verify audit chain integrity
GET  /api/v1/audit/checkpoints   # List audit checkpoints
POST /api/v1/audit/checkpoints   # Create audit checkpoint
```

## Node API

Node-facing endpoints used by Zentinel proxy instances.

### Register Node

```
POST /api/v1/projects/:project_slug/nodes/register
Auth: None (public endpoint)
```

**Request body**:
```json
{
  "name": "proxy-us-east-1",
  "labels": {"region": "us-east-1"},
  "version": "1.5.0",
  "capabilities": ["http2"]
}
```

**Response** (201):
```json
{
  "node_id": "uuid",
  "node_key": "base64-key",
  "poll_interval_s": 5
}
```

### Heartbeat

```
POST /api/v1/nodes/:node_id/heartbeat
Auth: Node key or JWT
```

**Request body**:
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

**Response** (200): Bundle metadata with presigned download URL, or 204 if no update available.

### Exchange Key for JWT

```
POST /api/v1/nodes/:node_id/token
Auth: Node key (X-Zentinel-Node-Key header)
```

**Response** (200):
```json
{
  "token": "eyJ...",
  "expires_at": "2026-02-17T05:00:00Z"
}
```

### Report Events

```
POST /api/v1/nodes/:node_id/events
Auth: Node key or JWT
```

**Request body**:
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

**Request body**:
```json
{
  "config_kdl": "route \"/api\" { upstream \"http://backend:8080\" }"
}
```

### Push Metrics

```
POST /api/v1/nodes/:node_id/metrics
Auth: Node key or JWT
```

**Request body**:
```json
{
  "metrics": [
    {
      "service_id": "uuid",
      "period_start": "2026-02-16T12:00:00Z",
      "request_count": 1500,
      "error_count": 3,
      "latency_p99_ms": 85,
      "status_2xx": 1450,
      "status_5xx": 3
    }
  ],
  "request_logs": [
    {
      "service_id": "uuid",
      "timestamp": "2026-02-16T12:01:00Z",
      "method": "GET",
      "path": "/api/users",
      "status": 200,
      "latency_ms": 45
    }
  ]
}
```

### Push WAF Events

```
POST /api/v1/nodes/:node_id/waf-events
Auth: Node key or JWT
```

**Request body**:
```json
{
  "events": [
    {
      "service_id": "uuid",
      "rule_type": "sqli",
      "rule_id": "CRS-942100",
      "action": "blocked",
      "severity": "critical",
      "client_ip": "192.168.1.100",
      "method": "POST",
      "path": "/api/login",
      "matched_data": "' OR 1=1 --"
    }
  ]
}
```

## Webhook API

Webhook endpoints for GitOps integrations. These verify the request signature and trigger bundle creation.

```
POST /api/v1/webhooks/github     # GitHub push events
POST /api/v1/webhooks/gitlab     # GitLab push events
POST /api/v1/webhooks/bitbucket  # Bitbucket push events
POST /api/v1/webhooks/gitea      # Gitea push events
POST /api/v1/webhooks/generic    # Generic webhook with HMAC verification
```

See [Integrations > GitOps Webhooks](integrations.md#gitops-webhooks) for setup.

## GraphQL API

```
POST /api/v1/graphql
Auth: API key (Authorization: Bearer)
```

The GraphQL endpoint provides query and mutation access to control plane resources. Absinthe subscriptions are available for real-time updates (e.g., alert state changes).

## Health Endpoints

```
GET /health    # Liveness check (no auth)
GET /ready     # Readiness check (no auth)
GET /metrics   # Prometheus metrics (no auth)
```

## Error Responses

All API errors follow a consistent format:

```json
{
  "error": "Short error description",
  "details": "Optional detailed message"
}
```

### Common Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (e.g., no bundle update) |
| 400 | Bad Request — validation errors |
| 401 | Unauthorized — missing or invalid credentials |
| 403 | Forbidden — insufficient scope |
| 404 | Not Found — resource or project not found |
| 409 | Conflict — duplicate resource |
| 422 | Unprocessable Entity — validation failure |
| 429 | Too Many Requests — rate limit exceeded |
| 500 | Internal Server Error |

### Rate Limit Headers

Rate-limited endpoints include these response headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1708099200
```

When rate limited (429), the response includes a `retry_after` value.
