# Configuration Management

This guide covers how to define and manage proxy configuration in Zentinel Control Plane. Configuration is modeled as structured resources (services, upstreams, certificates, etc.) that are compiled into immutable bundles for deployment.

## Services

Services are the primary configuration unit. Each service defines how Zentinel routes traffic for a specific path.

### Creating a Service

A service requires a **name** and **route path**. You then configure where traffic goes:

```
Name:        API Backend
Route Path:  /api/*
Upstream:    http://api.internal:8080
```

### Route Types

Services support several mutually exclusive routing modes:

| Mode | Description |
|------|-------------|
| **Upstream URL** | Forward to a single backend URL |
| **Upstream Group** | Forward to a load-balanced pool of backends |
| **Redirect** | Return an HTTP redirect to a different URL |
| **Static Response** | Return a fixed status code and body |

### Service Types

Services can be specialized for different protocols:

| Type | Description |
|------|-------------|
| `standard` | HTTP/HTTPS reverse proxy (default) |
| `inference` | LLM inference proxy with provider-specific config (OpenAI, Anthropic, generic) |
| `grpc` | gRPC service proxy |
| `websocket` | WebSocket proxy with upgrade support |
| `graphql` | GraphQL-aware proxy |
| `streaming` | Server-sent events / streaming proxy |

### Service Options

Each service supports a rich set of configuration options:

| Option | Description |
|--------|-------------|
| `timeout_seconds` | Backend request timeout |
| `retry` | Retry policy (attempts, backoff, retryable status codes) |
| `cache` | Response caching rules |
| `rate_limit` | Rate limiting configuration |
| `health_check` | Upstream health check settings |
| `headers` | Response header manipulation (add, remove, override) |
| `cors` | Cross-Origin Resource Sharing policy |
| `compression` | Response compression settings |
| `path_rewrite` | URL path rewriting rules |
| `traffic_split` | Weighted traffic splitting between upstreams |
| `access_control` | IP allowlist/denylist |
| `security` | Security headers, CSP, HSTS |
| `request_transform` | Modify requests before forwarding |
| `response_transform` | Modify responses before returning |

### Attaching Policies

Services can reference other configuration resources:

- **Certificate** — TLS certificate for HTTPS termination
- **Auth Policy** — Authentication and authorization policy
- **WAF Policy** — Web Application Firewall rules
- **OpenAPI Spec** — API documentation served at a configurable path

### Ordering

Services have a `position` field that determines evaluation order. Use the reorder API to change positions in bulk.

## Upstream Groups

Upstream groups define load-balanced pools of backend servers.

### Creating an Upstream Group

```
Name:       API Servers
Algorithm:  round_robin
```

Then add targets:

```
Target 1:  api-1.internal:8080  (weight: 100)
Target 2:  api-2.internal:8080  (weight: 100)
Target 3:  api-3.internal:8080  (weight: 50)
```

### Load Balancing Algorithms

| Algorithm | Description |
|-----------|-------------|
| `round_robin` | Rotate through targets sequentially (default) |
| `least_conn` | Route to the target with fewest active connections |
| `ip_hash` | Consistent hashing based on client IP |
| `consistent_hash` | Consistent hashing for cache-friendly distribution |
| `weighted` | Weighted random selection based on target weights |
| `random` | Random target selection |

### Target Properties

| Property | Description |
|----------|-------------|
| `host` | Backend hostname or IP |
| `port` | Backend port (1-65535) |
| `weight` | Load balancing weight (default: 100) |
| `max_connections` | Maximum concurrent connections to this target |
| `enabled` | Whether this target accepts traffic |

### Health Checks

Upstream groups support health checking of targets. Configure the check interval, timeout, healthy/unhealthy thresholds, and expected response.

### Sticky Sessions

Enable session affinity to route the same client to the same backend. Configure the cookie name and TTL.

### Circuit Breaker

Upstream groups support circuit breaker patterns. The control plane tracks circuit breaker state (`closed`, `open`, `half_open`) per upstream group per node, providing fleet-wide visibility into backend health.

### Trust Store

Upstream groups can reference a trust store containing CA certificates for verifying TLS connections to backends.

## TLS Certificates

Manage TLS certificates for HTTPS termination on proxy services.

### Uploading a Certificate

Provide the certificate PEM, private key PEM, and optionally a CA chain:

```
Name:          example.com
Domain:        example.com
Certificate:   (PEM content)
Private Key:   (PEM content)
CA Chain:      (PEM content, optional)
```

The control plane automatically:
- Encrypts the private key at rest (AES-256-GCM)
- Extracts metadata: issuer, validity dates, SANs, SHA256 fingerprint
- Tracks certificate status: `active`, `expiring_soon`, `expired`, `revoked`

### ACME / Let's Encrypt

Certificates support automatic renewal via ACME:

1. Enable **Auto Renew** on the certificate
2. Configure ACME settings (directory URL, contact email)
3. The control plane handles HTTP-01 challenges at `/.well-known/acme-challenge/:token`
4. Renewal status and errors are tracked

### Certificate Status

| Status | Description |
|--------|-------------|
| `active` | Valid and in use |
| `expiring_soon` | Expires within 30 days |
| `expired` | Past the `not_after` date |
| `revoked` | Manually revoked |

### Internal CA

Each project can have an internal Certificate Authority for issuing certificates used in service-to-service TLS (mTLS). The internal CA:

- Is created on demand via `get_or_create_internal_ca`
- Issues certificates with configurable subject CN/OU and key usage
- Tracks serial numbers, fingerprints, and revocation status
- Internal CA certificates are automatically included in compiled bundles

### Trust Stores

Trust stores are collections of CA certificates used by upstream groups to verify TLS connections to backend servers. They are useful when backends use private or self-signed certificates.

## Middlewares

Middlewares are reusable configuration blocks that can be attached to multiple services.

### Middleware Types

| Type | Description |
|------|-------------|
| `rate_limit` | Rate limiting with configurable windows and limits |
| `cache` | Response caching with TTL and key configuration |
| `cors` | CORS policy with origin, method, and header configuration |
| `compression` | Response compression (gzip, brotli) |
| `headers` | Header manipulation (add, remove, set) |
| `access_control` | IP allowlist/denylist |
| `security` | Security headers (CSP, HSTS, X-Frame-Options) |
| `path_rewrite` | URL path rewriting |
| `request_transform` | Request mutation |
| `response_transform` | Response mutation |
| `auth` | Authentication enforcement |
| `custom` | Custom middleware with arbitrary configuration |

### Attaching to Services

Middlewares are attached to services via service-middleware join records that support:

- **Position**: Execution order (lower numbers execute first)
- **Enabled**: Toggle the middleware for a specific service
- **Config Override**: Per-service configuration overrides

This allows a single rate limiter middleware to be shared across services with different limits per service.

## Plugins

Plugins extend Zentinel's functionality with custom code or configuration files.

### Plugin Properties

| Property | Description |
|----------|-------------|
| `name` | Display name |
| `slug` | URL-safe identifier |
| `description` | What the plugin does |
| `plugin_type` | `lua`, `wasm`, or `config` |
| `public` | Whether the plugin appears in the marketplace |
| `homepage_url` | Link to documentation or source |

### Plugin Versions

Plugins support versioning. Each version includes:

- **Version string**: Semantic version (e.g., "1.2.0")
- **Source code**: The plugin source (Lua, WASM, or config)
- **Storage key**: S3 path for compiled/packaged plugins
- **Checksum**: SHA256 hash for integrity verification
- **Changelog**: Release notes

### Service Plugins

Plugins are attached to services with per-service configuration. The plugin files are automatically included in compiled bundles.

### Marketplace

Plugins with `public: true` and no `project_id` appear in a shared marketplace, accessible to all projects.

## Secrets

Secrets store sensitive values (API keys, tokens, passwords) that are referenced in service configurations.

### Secret Properties

| Property | Description |
|----------|-------------|
| `name` | Display name |
| `key` | Reference key used in configurations (unique per project) |
| `value` | Encrypted at rest (AES-256-GCM), never exposed in API responses |
| `description` | Optional description |
| `environment_id` | Optional environment scoping |
| `expires_at` | Optional expiration date |
| `last_rotated_at` | Timestamp of last rotation |

### Secret Rotation

When a secret is updated, the `last_rotated_at` timestamp is recorded and a `secret.rotated` event is emitted for notification routing.

### Environment Scoping

Secrets can be scoped to a specific environment, allowing different values for dev, staging, and production.

## Auth Policies

Auth policies define authentication and authorization requirements for services.

### Policy Types

| Type | Description |
|------|-------------|
| `jwt` | Validate JWT tokens with configurable issuer, audience, and algorithms |
| `api_key` | Validate API keys from headers or query parameters |
| `basic` | HTTP Basic Authentication |
| `oauth2` | OAuth 2.0 token introspection |
| `oidc` | OpenID Connect token validation |
| `custom` | Custom authentication with arbitrary configuration |
| `composite` | Combine multiple policies with AND/OR logic |

### Policy Configuration

Each policy type has type-specific settings. For example, a JWT policy:

```json
{
  "issuer": "https://auth.example.com",
  "audience": "api.example.com",
  "algorithms": ["RS256", "ES256"],
  "jwks_url": "https://auth.example.com/.well-known/jwks.json"
}
```

Auth policies are attached to services and enforced by the proxy at request time.

See [Security > Auth Policies](security.md#auth-policies) for more details.

## OpenAPI Specifications

Import OpenAPI 3.x specifications to automatically generate service configurations.

### Importing an OpenAPI Spec

Upload a JSON or YAML OpenAPI specification. The parser:

1. Validates the spec version (supports OpenAPI 3.0.x and 3.1.x)
2. Extracts server URL, base path, and upstream
3. Converts path templates (e.g., `/users/{id}`) to wildcard patterns (`/users/*`)
4. Extracts methods, tags, descriptions, and security schemes for each path
5. Maps security schemes to auth policy configurations

### Spec Diffing

Compare two OpenAPI specs to see added, removed, and unchanged paths. This is useful for reviewing API changes before creating a new bundle.

### Developer Portal

When enabled, OpenAPI specs power a developer portal that provides:

- Interactive API documentation
- Path listing with methods and descriptions
- Authentication requirements

See [Integrations > Developer Portal](integrations.md#developer-portal) for setup.

## Service Templates

Service templates provide reusable starting points for common service configurations. Templates include pre-configured settings for route paths, upstream configuration, middlewares, and security policies.

## Config Import/Export

The control plane supports importing and exporting full project configurations:

- **Export**: Generate a JSON representation of all services, upstreams, middlewares, and policies
- **Import**: Apply a configuration snapshot to a project
- **Diff**: Compare two configuration snapshots to review changes

This supports infrastructure-as-code workflows and environment replication.
