# Zentinel Control Plane — Feature Roadmap v2

> Competitive feature roadmap based on analysis of nevisAdmin4, HAProxy Fusion,
> NGINX One, Traefik Hub, Kong Konnect, and Envoy/Istio control planes.
>
> **Goal:** Make Zentinel CP a "single pane of glass" where everything can be
> configured and deployed through one application (inspired by nevisAdmin4).

---

## Current State (Implemented)

### Core Infrastructure (Phases 1–7 + v1.1 — Complete)
- [x] Services CRUD with route patterns, single upstream, timeouts, retry, cache, rate limiting, health checks, headers
- [x] KDL config generation from structured services
- [x] Bundle lifecycle (compile, sign Ed25519, SBOM CycloneDX, risk scoring)
- [x] Rolling deployments with health gates, pause/resume/rollback
- [x] Scheduled rollouts with calendar view
- [x] Approval workflows for rollouts
- [x] Rollout templates
- [x] Node management (registration, heartbeat, label-based targeting, stale detection)
- [x] Node groups (label-based organization)
- [x] Drift detection with auto-resolve and severity levels
- [x] Multi-tenant (organizations, projects, scoped API keys, RBAC)
- [x] Multi-environment (dev → staging → prod) with bundle promotion
- [x] GitOps (GitHub webhook auto-compile on push)
- [x] Audit logging with export
- [x] Config validation rules (required field, forbidden/allowed pattern, JSON schema)
- [x] Prometheus metrics (PromEx), structured JSON logging, health endpoints
- [x] LiveView UI (dashboard, nodes, bundles, rollouts, drift, environments, approvals, audit, profile)
- [x] Node simulator for testing rollout logic
- [x] OpenAPI 3.1 spec with Scalar API docs
- [x] E2E tests (Wallaby) + CI pipeline

---

## Phase 8 — Full Proxy Configuration (Complete)

> Make Zentinel CP capable of configuring all core proxy features through the UI.
> Every competitor has these — they are table stakes.

### 8.1 TLS / Certificate Management — DONE
- [x] Certificate CRUD (upload PEM/DER certs and private keys) — `certificate.ex` schema + `certificate_crypto.ex` AES-256-GCM encryption
- [x] Certificate-to-service binding (assign certs to virtual hosts / services) — `Service.certificate_id` FK
- [x] Certificate expiry tracking with dashboard warnings — `certificate_expiry_worker.ex` Oban worker, statuses: active/expiring_soon/expired/revoked
- [x] Auto-renewal integration (Let's Encrypt / ACME) — `acme/client.ex`, `acme/renewal.ex`, `acme/crypto.ex`, `certificate_renewal_worker.ex`
- [x] Internal CA for inter-node mTLS (inspired by nevisAdmin4 auto-PKI) — `internal_ca.ex`, `internal_ca_live/`
- [x] Trust store management (CA bundles for upstream verification) — `trust_store.ex`, `trust_stores_live/`
- [x] KDL generation for TLS blocks — `kdl_generator.ex` `build_tls_certificates` + `build_tls_ref`

### 8.2 Upstream Groups / Load Balancing — DONE
- [x] Upstream group schema (named group of backend servers) — `upstream_group.ex`
- [x] Multiple backends per upstream group (host, port, weight) — `upstream_target.ex`
- [x] Load balancing algorithms (round_robin, least_conn, ip_hash, consistent_hash, weighted, random)
- [x] Passive health checks (mark unhealthy on failure threshold) — `health_check` map field
- [x] Active health checks (periodic probes to backends)
- [x] Service-to-upstream-group binding (replace single `upstream_url`) — `Service.upstream_group_id` FK
- [x] Upstream group CRUD UI + API — `upstream_groups_live/`, `upstream_group_controller.ex`
- [x] KDL generation for upstream blocks — `build_upstream_groups`, `build_upstream_group_block`

### 8.3 IP Access Control — DONE
- [x] Global allow/deny lists (CIDR notation) — `ProjectConfig.global_access_control`
- [x] Per-service allow/deny lists — `Service.access_control`
- [x] Precedence rules (deny overrides allow, or configurable) — `mode: "deny_first"`
- [x] IP list CRUD UI + API — service edit forms + controller
- [x] KDL generation for access control blocks — `build_access_control_block`, `build_global_access_control`

### 8.4 CORS Configuration — DONE
- [x] Per-service CORS policy (allowed origins, methods, headers, credentials, max-age) — `Service.cors`
- [x] Global default CORS policy with per-service overrides — `ProjectConfig.default_cors`
- [x] CORS settings in service edit form — 5 CORS fields in LiveView forms
- [x] KDL generation for CORS blocks — `build_cors_block`

### 8.5 Redirect / Rewrite Rules — DONE
- [x] URL redirect rules (301/302/307/308) with pattern matching — `Service.redirect_url` + `respond_status`
- [x] Path rewrite rules (prefix strip, regex replace) — `Service.path_rewrite`
- [x] Host-based routing / virtual hosts — via route_path matching
- [x] Rule ordering and priority — `Service.position`
- [x] Redirect/rewrite CRUD UI + API — LiveView forms with rewrite fields
- [x] KDL generation for redirect/rewrite blocks — `build_path_rewrite_block`, redirect in `build_route`

### 8.6 Compression — DONE
- [x] Global compression settings (gzip, brotli, zstd) — `ProjectConfig.default_compression`
- [x] Per-service compression overrides — `Service.compression`
- [x] Configurable min size, content-type filters
- [x] KDL generation for compression blocks — `build_compression_block`, `build_global_compression`

---

## Phase 9 — Security & Resilience (Complete)

> Match enterprise expectations for proxy security and reliability features.

### 9.1 Circuit Breakers — DONE
- [x] Per-upstream circuit breaker configuration — `UpstreamGroup.circuit_breaker` map field
- [x] Configurable thresholds (failure_threshold, success_threshold, timeout, half_open_max_requests)
- [x] Half-open state with configurable probe interval
- [x] Circuit breaker status in node/service health views — `circuit_breaker_status.ex`, upstream group show page
- [x] KDL generation for circuit breaker blocks — `build_nested_map_block` via upstream group

### 9.2 Proxy-Level Authentication — DONE
- [x] JWT validation (issuer, audience, JWKS URL, claim requirements) — `AuthPolicy` auth_type "jwt"
- [x] API key authentication (header or query param) — auth_type "api_key"
- [x] Basic auth (htpasswd-style user lists) — auth_type "basic"
- [x] Forward auth (delegate to external auth service) — auth_type "forward_auth"
- [x] mTLS client certificate validation — auth_type "mtls"
- [x] Auth policy binding to services (which auth method applies where) — `Service.auth_policy_id` FK
- [x] Auth configuration UI + API — `auth_policies_live/`, `auth_policy_controller.ex`
- [x] KDL generation for auth blocks — `build_auth_block`

### 9.3 WAF / Request Security — DONE
- [x] Request size limits (max body, max headers, max URI length) — `security.max_body_size`
- [x] Content-type enforcement (whitelist allowed content types)
- [x] Common attack pattern detection (SQLi, XSS, path traversal, RFI) — `security.block_sqli`, `security.block_xss`
- [x] Custom WAF rules (regex-based block/allow) — via middleware system with custom type
- [x] Request rate anomaly detection — `waf_baseline.ex`, `waf_baseline_worker.ex`, `waf_anomaly.ex`, anomalies live view
- [x] WAF event logging and dashboard — `waf_event.ex`, `waf_live/index.ex`, `waf_live/show.ex`, time-series chart
- [x] Per-service WAF policy (enable/disable, sensitivity level) — `Service.security` map
- [x] KDL generation for security blocks — `build_security_block`, `build_global_security`

### 9.4 Request / Response Transformation — DONE
- [x] Header manipulation (add, remove, rename, rewrite — request and response) — `Service.headers`, `Service.request_transform`
- [x] URL path rewriting (beyond simple redirects — dynamic path manipulation) — `Service.path_rewrite`
- [x] Query parameter manipulation (add, remove, rename) — via request_transform
- [x] Request/response body transformation (JSON field filtering, renaming) — `Service.request_transform`, `Service.response_transform`
- [x] Conditional transformations (apply based on path, header, method) — via middleware config overrides
- [x] KDL generation for transformation blocks — `build_request_transform_block`, `build_response_transform_block`

---

## Phase 10 — Traffic Intelligence (Complete)

> Advanced traffic management features that differentiate Zentinel CP.

### 10.1 Traffic Splitting / Weighted Routing — DONE
- [x] Weight-based routing between upstream groups (canary at the proxy level) — `Service.traffic_split`
- [x] Header-based routing (route by header value, e.g., `X-Version: v2`) — `match_rules` with type "header"
- [x] Cookie-based routing (sticky sessions, A/B testing) — `match_rules` with type "cookie"
- [x] Gradual traffic shift (time-based progression from 0% → 100%)
- [x] Traffic split visualization in UI
- [x] KDL generation for traffic split blocks — `build_traffic_split_block`

### 10.2 Configuration Templates / Patterns — DONE
- [x] Template schema (named template with typed parameters and defaults) — `service_template.ex`
- [x] Built-in template library (11 templates): REST API, Web App, WebSocket, Static Files, Auth-Protected, Health Endpoint, LLM Inference Gateway, gRPC Gateway, WebSocket Gateway, GraphQL Gateway, SSE Streaming Service
- [x] Custom template creation and management — per-project templates
- [x] "Create service from template" workflow in UI — `services_live/new.ex` template selection
- [x] Template versioning — `version` field
- [x] KDL generation from template instantiation

### 10.3 Enhanced Configuration Diff Viewer — DONE
- [x] Side-by-side diff of generated KDL (current deployed vs. pending) — `bundles_live/diff.ex` unified/side-by-side toggle
- [x] Semantic diff (not just text — highlight added/removed/changed services) — `bundles/diff.ex` manifest_diff
- [x] Fullscreen diff mode — `toggle_fullscreen` event
- [x] Diff as part of deployment/rollout wizard
- [x] Historical diff between any two bundles — accepts `a` and `b` bundle IDs

### 10.4 Request-Level Analytics Dashboard — DONE
- [x] Per-service request rate, latency (p50/p95/p99), error rate — `analytics.ex` `get_service_metrics`
- [x] Top consumers (by IP, API key, or header) — `service_metric.ex` `top_consumers` field
- [x] Status code distribution over time — status_2xx/3xx/4xx/5xx fields
- [x] Bandwidth usage per service — bandwidth_in_bytes, bandwidth_out_bytes
- [x] Real-time request log viewer (tail -f style) — `request_log.ex` + `get_recent_logs`
- [x] Time-range filtering and comparison — `analytics_live/index.ex` time range selector

---

## Phase 11 — Platform Features (Complete)

> Move from proxy management tool to full platform. These features unlock new
> use cases and user segments.

### 11.1 OpenAPI Import — DONE
- [x] Upload OpenAPI 3.x spec (YAML or JSON) — `openapi_import_controller.ex`
- [x] Auto-generate services + routes from spec paths and operations — `openapi_parser.ex` `extract_services`
- [x] Map OpenAPI security schemes to proxy auth policies — `extract_auth_policies`
- [x] Detect changes on re-import (add new routes, flag removed routes) — `openapi_spec.ex` checksum tracking
- [x] Link spec to service for documentation — `Service.openapi_spec_id` FK + `Service.openapi_path`
- [x] Preview generated services before applying — dedicated preview endpoint

### 11.2 Service Discovery Integration — DONE
- [x] Consul service discovery (watch for backend changes, auto-update upstream groups) — `consul_resolver.ex`
- [x] Kubernetes service discovery (watch Services/Endpoints) — `k8s_resolver.ex`
- [x] DNS-based discovery (SRV records) — `discovery_source.ex`, `dns_resolver.ex`, `dns_resolver/inet.ex`
- [x] Manual refresh + auto-sync toggle — `discovery_sync_worker.ex` background worker
- [x] Discovery source status in UI — `last_synced_at`, `last_sync_status`, `last_sync_error`, `last_sync_targets_count`

### 11.3 Middleware / Plugin System — DONE
- [x] Middleware chain model (ordered list of middleware per service) — `middleware.ex`, `service_middleware.ex`
- [x] Built-in middleware types (11): rate_limit, cache, cors, compression, headers, access_control, security, path_rewrite, request_transform, response_transform, auth, custom
- [x] Custom middleware (user-defined with typed config schema) — `custom` type with `kdl_block_name`
- [x] Middleware library (browse + attach to services) — `middlewares_live/`
- [x] Middleware ordering drag-and-drop in UI — `service_middleware.position`
- [x] KDL generation for middleware chains — `build_middleware_chain`, `build_middleware_block`

### 11.4 Visual Service Topology — DONE
- [x] Graph view showing: client → proxy → services → upstream groups → backends — `topology_live/index.ex`
- [x] Live status overlay (healthy/unhealthy/degraded on each node) — `get_topology_data`, 10s auto-refresh
- [x] Click-through from graph to service/upstream detail — `navigate` event handler
- [x] Filter by environment, node group, or label
- [x] Real-time updates via LiveView

### 11.5 Developer Portal — DONE
- [x] Public-facing portal for API consumers — `portal.ex` context, `portal_live/`
- [x] Auto-generated API documentation from OpenAPI specs — `portal_live/docs.ex`
- [x] Interactive API testing console (try-it-out) — `portal_live/console.ex` with `execute_request`
- [x] API key self-service (request, view, rotate keys) — `portal_live/keys.ex`
- [x] Customizable portal branding — `portal_title`, `portal_custom_css`, `portal_logo_url`
- [x] Usage analytics per API consumer

### 11.6 Secrets Management — DONE
- [x] Secrets store (encrypted at rest, scoped to project or environment) — `secrets/secret.ex`, `secret_crypto.ex` AES-GCM
- [x] Secret references in service config (e.g., `${secrets.NAME}`) — `secrets.ex` reference pattern
- [x] Secret injection into KDL at compile time (never stored in bundles in plaintext) — `kdl_generator.ex` `maybe_resolve_secrets`
- [x] Vault integration (HashiCorp Vault as external secrets backend) — `vault_client.ex`, `vault_config.ex`
- [x] Secret rotation workflows — `secrets.ex` `rotate_secret`, `last_rotated_at` tracking
- [x] Audit logging for secret access — audit logs on create/update/rotate

---

## Completed Stretch Goals

All originally-identified stretch goals have been implemented:

| Feature | Phase | Status |
|---------|-------|--------|
| ACME / Let's Encrypt auto-renewal | 8.1 | Done — `acme/client.ex`, `acme/renewal.ex`, `certificate_renewal_worker.ex` |
| Internal CA for mTLS | 8.1 | Done — `internal_ca.ex`, `internal_ca_live/` |
| Trust store management | 8.1 | Done — `trust_store.ex`, `trust_stores_live/` |
| Circuit breaker health view status | 9.1 | Done — `circuit_breaker_status.ex`, upstream group show page |
| WAF anomaly detection | 9.3 | Done — `waf_baseline.ex`, `waf_baseline_worker.ex`, `waf_anomaly.ex` |
| WAF event logging dashboard | 9.3 | Done — `waf_event.ex`, `waf_live/index.ex`, `waf_live/show.ex` |
| Consul service discovery | 11.2 | Done — `consul_resolver.ex` |
| Kubernetes service discovery | 11.2 | Done — `k8s_resolver.ex` |
| Vault integration for secrets | 11.6 | Done — `vault_client.ex`, `vault_config.ex` |

---

## Competitive Positioning

### Where Zentinel CP Can Win
1. **Unified config-to-deploy pipeline** — nevisAdmin4-style "configure everything and
   deploy from one place" but for a general-purpose proxy (not vendor-locked)
2. **Immutable, signed bundles** — unique in the space; most competitors do live config
   pushes. Zentinel's compile→sign→distribute model is inherently safer.
3. **Pull-based distribution** — nodes pull verified bundles rather than receiving pushes.
   Better security posture than HAProxy Fusion or NGINX One push models.
4. **Configuration templates with best practices** — nevisAdmin4's strongest idea,
   applied to a general-purpose proxy instead of a proprietary ecosystem.
5. **LiveView real-time UI** — Phoenix LiveView gives real-time updates without the
   complexity of a separate SPA frontend.

### Where Competitors Are Ahead
1. **WAF maturity** — HAProxy and NGINX/F5 have years of WAF signature development
2. **Plugin ecosystem** — Kong's 100+ plugins are hard to replicate
3. **API lifecycle management** — Kong Konnect and Traefik Hub are full API platforms
4. **Service mesh** — Istio/Envoy own this space; Zentinel is not a mesh
5. **AI-assisted config** — NGINX One has AI config assistance (potential future feature)

---

## References

- [nevisAdmin4 Documentation](https://docs.nevis.net/nevisadmin4/)
- [HAProxy Fusion Control Plane](https://www.haproxy.com/products/haproxy-fusion-control-plane)
- [NGINX One Console](https://www.f5.com/products/nginx/one-console)
- [Traefik Hub](https://traefik.io/traefik-hub)
- [Kong Konnect](https://konghq.com/products/kong-konnect)
- [Istio Architecture](https://istio.io/latest/docs/ops/deployment/architecture/)
- [Envoy Gateway](https://gateway.envoyproxy.io/)
