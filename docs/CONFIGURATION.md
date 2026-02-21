# Configuration

## Services

Services are the primary configuration unit. Each maps an HTTP route path to a backend.

### Route Types

| Mode | Description |
|------|-------------|
| **Upstream URL** | Forward to a single backend URL |
| **Upstream Group** | Forward to a load-balanced pool |
| **Redirect** | Return HTTP redirect |
| **Static Response** | Return fixed status + body |

### Service Types

| Type | Description |
|------|-------------|
| `standard` | HTTP/HTTPS reverse proxy (default) |
| `inference` | LLM inference proxy (OpenAI, Anthropic, generic) |
| `grpc` | gRPC service proxy |
| `websocket` | WebSocket with upgrade support |
| `graphql` | GraphQL-aware proxy |
| `streaming` | SSE / streaming proxy |

### Service Options

| Option | Description |
|--------|-------------|
| `timeout_seconds` | Backend request timeout |
| `retry` | Retry policy (attempts, backoff, retryable codes) |
| `cache` | Response caching rules |
| `rate_limit` | Rate limiting config |
| `health_check` | Upstream health check settings |
| `headers` | Response header manipulation (add/remove/override) |
| `cors` | CORS policy |
| `compression` | Response compression (gzip, brotli) |
| `path_rewrite` | URL path rewriting |
| `traffic_split` | Weighted traffic splitting |
| `access_control` | IP allowlist/denylist |
| `security` | Security headers (CSP, HSTS, X-Frame-Options) |
| `request_transform` | Modify requests before forwarding |
| `response_transform` | Modify responses before returning |

### Attachments

Services can reference: **Certificate** (TLS termination), **Auth Policy** (authentication), **WAF Policy** (firewall rules), **OpenAPI Spec** (developer portal docs).

Ordering: services have a `position` field. Use the reorder API to change positions in bulk.

## Upstream Groups

Load-balanced pools of backend servers.

### Algorithms

| Algorithm | Description |
|-----------|-------------|
| `round_robin` | Sequential rotation (default) |
| `least_conn` | Fewest active connections |
| `ip_hash` | Consistent hashing on client IP |
| `consistent_hash` | Cache-friendly distribution |
| `weighted` | Weighted random selection |
| `random` | Random |

### Target Properties

| Property | Description |
|----------|-------------|
| `host` | Backend hostname or IP |
| `port` | Backend port (1-65535) |
| `weight` | Load balancing weight (default: 100) |
| `max_connections` | Max concurrent connections |
| `enabled` | Whether target accepts traffic |

Features: health checks, sticky sessions (cookie-based), circuit breaker (closed/open/half_open), trust stores (CA certs for backend TLS verification).

## TLS Certificates

Upload PEM cert + private key + optional CA chain.

Auto-extraction: issuer, validity dates, SANs, SHA256 fingerprint. Private key encrypted at rest (AES-256-GCM).

| Status | Description |
|--------|-------------|
| `active` | Valid and in use |
| `expiring_soon` | Expires within 30 days |
| `expired` | Past `not_after` date |
| `revoked` | Manually revoked |

### ACME / Let's Encrypt

1. Enable Auto Renew on the certificate
2. Configure ACME settings (directory URL, contact email)
3. Control plane handles HTTP-01 challenges at `/.well-known/acme-challenge/:token`
4. Renewal status tracked

### Internal CA

Per-project internal CA for mTLS between services. Created on demand. Issues certificates with configurable subject CN/OU and key usage. CA certs automatically included in compiled bundles.

## Middlewares

Reusable config blocks attached to multiple services:

| Type | Description |
|------|-------------|
| `rate_limit` | Rate limiting with windows and limits |
| `cache` | Response caching with TTL |
| `cors` | CORS policy |
| `compression` | gzip, brotli |
| `headers` | Header manipulation |
| `access_control` | IP allowlist/denylist |
| `security` | Security headers |
| `path_rewrite` | URL path rewriting |
| `request_transform` | Request mutation |
| `response_transform` | Response mutation |
| `auth` | Authentication enforcement |
| `custom` | Arbitrary configuration |

Attach to services with per-service `position` (execution order) and optional config override.

## Plugins

| Type | Description |
|------|-------------|
| `lua` | Lua scripts |
| `wasm` | WebAssembly modules |
| `config` | Configuration files |

Versioned with checksums. Attached to services with per-service config. Public plugins appear in a shared marketplace.

## Secrets

Encrypted at rest (AES-256-GCM). Never exposed in API responses.

| Property | Description |
|----------|-------------|
| `key` | Reference key in configurations (unique per project) |
| `value` | Encrypted value |
| `environment_id` | Optional environment scoping |
| `expires_at` | Optional expiration |
| `last_rotated_at` | Rotation tracking |

Rotation triggers `secret.rotated` event for notification routing.

## OpenAPI Specs

Import OpenAPI 3.x to auto-generate service configurations:

1. Validates spec version (3.0.x, 3.1.x)
2. Extracts server URL, base path, upstream
3. Converts path templates (`/users/{id}`) to wildcards (`/users/*`)
4. Maps security schemes to auth policies

Spec diffing available. Powers the developer portal when enabled.

## Service Templates

Reusable starting points for common service patterns. Include pre-configured routes, upstreams, middlewares, and policies.

## Config Import/Export

- **Export**: JSON snapshot of all services, upstreams, middlewares, policies
- **Import**: Apply config snapshot to a project
- **Diff**: Compare two snapshots

Supports infrastructure-as-code workflows and environment replication.

## GitOps Integration

Link a project to a Git repository:

| Setting | Description |
|---------|-------------|
| `repository` | Owner/repo (e.g., `acme/proxy-config`) |
| `branch` | Target branch (default: `main`) |
| `config_path` | KDL config file path (default: `zentinel.kdl`) |

Push to the configured branch triggers automatic bundle compilation via webhook.

Supported providers: GitHub, GitLab, Bitbucket, Gitea, generic (HMAC-verified).

## Environment Variables

### Runtime (`config/runtime.exs`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Prod | — | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Prod | — | Phoenix secret (generate: `mix phx.gen.secret`) |
| `PHX_HOST` | Prod | `localhost` | Public hostname |
| `PORT` | No | `4000` | HTTP port |
| `S3_BUCKET` | Yes | `zentinel-bundles` | Bundle storage bucket |
| `S3_ENDPOINT` | Yes | `http://localhost:9000` | S3 endpoint |
| `S3_ACCESS_KEY_ID` | Yes | — | S3 access key |
| `S3_SECRET_ACCESS_KEY` | Yes | — | S3 secret key |
| `S3_REGION` | No | `us-east-1` | S3 region |
| `ZENTINEL_BINARY` | No | `zentinel` | Path to zentinel CLI |
| `GITHUB_WEBHOOK_SECRET` | No | — | GitHub webhook HMAC secret |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | — | OpenTelemetry endpoint |
| `FORCE_SSL` | No | `false` | Redirect HTTP → HTTPS |
| `POOL_SIZE` | No | `10` | DB connection pool size |

### Config Files

| File | Purpose |
|------|---------|
| `config/config.exs` | Compile-time config (adapter, PubSub, Oban queues) |
| `config/dev.exs` | Dev overrides (SQLite, hot reload, local mailer) |
| `config/test.exs` | Test overrides (SQLite, test settings) |
| `config/prod.exs` | Prod overrides (PostgreSQL, SSL, releases) |
| `config/runtime.exs` | Runtime config (env vars, secrets) |

### Oban Queues

```elixir
config :zentinel_cp, Oban,
  queues: [default: 10, rollouts: 5, maintenance: 2]
```

### Bundle Signing

```elixir
config :zentinel_cp, :bundle_signing,
  enabled: true,
  private_key_path: "/secrets/signing-key.pem",
  public_key_path: "/secrets/signing-key.pub",
  key_id: "key-2024-01"
```
