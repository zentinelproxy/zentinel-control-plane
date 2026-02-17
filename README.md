<div align="center">

<h1 align="center">
  Zentinel Control Plane
</h1>

<p align="center">
  <em>Fleet management for Zentinel reverse proxies.</em><br>
  <em>Declarative configuration distribution with safe rollouts.</em>
</p>

<p align="center">
  <a href="https://elixir-lang.org/">
    <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.17+-4B275F?logo=elixir&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.phoenixframework.org/">
    <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-f5a97f?style=for-the-badge">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-Apache--2.0-c6a0f6?style=for-the-badge">
  </a>
</p>

<p align="center">
  <a href="https://github.com/zentinelproxy/zentinel">Zentinel Proxy</a> •
  <a href="docs/index.md">Documentation</a> •
  <a href="https://github.com/zentinelproxy/zentinel/discussions">Discussions</a>
</p>

</div>

---

Zentinel Control Plane is a fleet management system for [Zentinel](https://github.com/zentinelproxy/zentinel) reverse proxies. It handles configuration distribution, rolling deployments, and real-time node monitoring — built with Elixir/Phoenix and LiveView.

<p align="center">
  <img src="priv/static/images/dashboard-screenshot.png" alt="Zentinel Control Plane Dashboard" width="800">
</p>

## Status

**Beta.** The core workflow (compile config → create bundle → roll out to nodes) works end-to-end. Multi-tenant support, audit logging, drift detection, approval workflows, and the full LiveView UI are implemented. Actively being hardened for production use.

## How It Works

```
KDL Config → Compile & Sign → Immutable Bundle → Rollout → Nodes Pull & Activate
```

1. **Upload** a KDL configuration (validated via `zentinel validate`)
2. **Compile** into an immutable, signed bundle (tar.zst with manifest, checksums, SBOM)
3. **Create a rollout** targeting nodes by label selectors
4. **Orchestrate** batched deployment with health gates, pause/resume/rollback
5. **Nodes pull** the bundle, verify the signature, stage, and activate

Every mutation is audit-logged with actor, action, and diff.

## Features

| Feature | Description |
|---------|-------------|
| **Bundle Management** | Immutable, content-addressed config artifacts with deterministic SHA256 hashing |
| **Bundle Signing** | Ed25519 signatures with cryptographic verification on every node |
| **SBOM Generation** | CycloneDX 1.5 for every bundle — supply chain visibility out of the box |
| **Rolling Deployments** | Batched rollouts with configurable batch size, health gates, and progress deadlines |
| **Scheduled Rollouts** | Schedule deployments for future execution with calendar view |
| **Approval Workflows** | Require approval before rollouts execute with audit trail |
| **Rollout Templates** | Reusable rollout configurations for consistent deployments |
| **Drift Detection** | Automatic detection when node config diverges from expected state |
| **Node Management** | Registration, heartbeat tracking, label-based targeting, stale detection |
| **Node Groups** | Organize nodes with label-based groups for targeted operations |
| **Environments** | Promotion pipeline (dev → staging → prod) with bundle tracking |
| **Multi-Tenant** | Organizations, projects, and scoped API keys with RBAC |
| **GitOps** | GitHub webhook integration — auto-compile bundles on push |
| **Audit Logging** | Every mutation logged with who, what, when, and resource diff |
| **SLO/SLI Monitoring** | Define SLOs with error budget tracking and burn rate alerts |
| **Alerting** | Threshold, anomaly, and SLO burn rate alert rules with silencing |
| **WAF** | ~60 OWASP CRS rules, policy system, anomaly detection, analytics |
| **SSO** | OIDC (with PKCE) and SAML 2.0 with JIT provisioning and group mapping |
| **TOTP MFA** | Time-based one-time passwords with recovery codes |
| **Notifications** | Route events to Slack, PagerDuty, Teams, Email, or webhooks |
| **Service Topology** | Visual graph of services, upstreams, middlewares, and policies |
| **GraphQL API** | Absinthe-powered with real-time subscriptions |
| **Developer Portal** | Auto-generated API docs from OpenAPI specs per project |
| **Observability** | Prometheus metrics, OpenTelemetry tracing, structured JSON logging |
| **LiveView UI** | K8s-style sidebar layout with real-time updates across all views |
| **Node Simulator** | Built-in fleet simulator for testing rollout logic without real nodes |

## UI Overview

The control plane provides a comprehensive LiveView UI with real-time updates:

| Page | Path | Description |
|------|------|-------------|
| **Dashboard** | `/orgs/:org/dashboard` | Fleet overview with node status, active rollouts, and drift alerts |
| **Nodes** | `.../nodes` | Node list with status, labels, bundle versions, and health |
| **Bundles** | `.../bundles` | Bundle management with diff viewer, SBOM inspector, and promotion pipeline |
| **Rollouts** | `.../rollouts` | Rollout list with progress tracking, controls, and node-level status |
| **Services** | `.../services` | Service routing configuration with upstream, middleware, and policy attachment |
| **Topology** | `.../topology` | Visual service graph showing services, upstreams, and policies |
| **Certificates** | `.../certificates` | TLS certificate management with ACME/Let's Encrypt support |
| **Drift** | `.../drift` | Drift events with filtering and manual resolution |
| **Node Groups** | `.../node-groups` | Label-based node organization |
| **Environments** | `.../environments` | Promotion pipeline configuration |
| **SLOs** | `.../slos` | SLO definitions with error budget tracking and burn rate |
| **Alerts** | `.../alerts` | Alert rules with firing state, silencing, and acknowledgment |
| **WAF** | `.../waf-policies` | WAF policy management with rule overrides and analytics |
| **Notifications** | `.../notifications` | Notification channels and routing rules with delivery tracking |
| **Secrets** | `.../secrets` | Encrypted secret management with rotation and environment scoping |
| **Webhooks** | `.../webhooks` | GitHub integration configuration |
| **Schedule** | `/schedule` | Calendar view of scheduled rollouts |
| **Approvals** | `/approvals` | Pending rollout approval queue |
| **API Keys** | `/api-keys` | Scoped API key management |
| **Audit Log** | `/audit` | Searchable audit trail with export |
| **Profile** | `/profile` | User settings and MFA configuration |

## Quick Start

### Docker Compose (Recommended)

The fastest way to get running. Starts the control plane, PostgreSQL, and MinIO with a single command:

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane
docker compose up
```

This builds the image, runs database migrations automatically, and serves the control plane at [localhost:4000](http://localhost:4000). MinIO console is available at [localhost:9001](http://localhost:9001) (credentials: `minioadmin` / `minioadmin`).

### Local Development

For development with hot-reloading and SQLite (no external databases needed):

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane
mise install
mise run setup
mise run dev
```

Visit [localhost:4000](http://localhost:4000).

**Prerequisites:** [mise](https://mise.jdx.dev/) (manages Elixir/OTP), Docker (for MinIO), and optionally a [Zentinel](https://github.com/zentinelproxy/zentinel) binary for config validation.

### Development Commands

```bash
mise run dev              # Start interactive dev server (iex -S mix phx.server)
mise run test             # Run test suite
mise run test:coverage    # Run tests with coverage report
mise run check            # Run format check, credo, and tests
mise run lint             # Run Credo static analysis
mise run format           # Format all Elixir files
mise run db:reset         # Drop, create, and migrate database
mise run db:migrate       # Run pending migrations
mise run routes           # List all routes
```

## API

**📚 Interactive API Documentation:** [/api/docs](http://localhost:4000/api/docs) — powered by [Scalar](https://github.com/scalar/scalar)

### Node API

Nodes authenticate with registration keys or JWT tokens.

```
POST /api/v1/projects/:slug/nodes/register   # Register a node
POST /api/v1/nodes/:id/heartbeat             # Send heartbeat
GET  /api/v1/nodes/:id/bundles/latest        # Fetch latest bundle
POST /api/v1/nodes/:id/token                 # Refresh JWT token
```

### Control Plane API

Authenticated via scoped API keys (`nodes:read`, `bundles:write`, `rollouts:write`, etc).

```
# Bundles
GET/POST       /api/v1/projects/:slug/bundles              # List / create bundles
GET            /api/v1/projects/:slug/bundles/:id/download # Download bundle artifact
GET            /api/v1/projects/:slug/bundles/:id/sbom     # Download SBOM (CycloneDX)
POST           /api/v1/projects/:slug/bundles/:id/revoke   # Revoke a compromised bundle

# Rollouts
GET/POST       /api/v1/projects/:slug/rollouts             # List / create rollouts
POST           /api/v1/projects/:slug/rollouts/:id/pause   # Pause rollout
POST           /api/v1/projects/:slug/rollouts/:id/resume  # Resume rollout
POST           /api/v1/projects/:slug/rollouts/:id/rollback # Rollback to previous bundle

# Nodes
GET            /api/v1/projects/:slug/nodes                # List nodes
GET            /api/v1/projects/:slug/nodes/stats          # Fleet statistics

# Drift Detection
GET            /api/v1/projects/:slug/drift                # List drift events
GET            /api/v1/projects/:slug/drift/stats          # Drift statistics
POST           /api/v1/projects/:slug/drift/:id/resolve    # Resolve drift event

# API Key Management (requires api_keys:admin scope)
GET/POST       /api/v1/api-keys                            # List / create API keys
POST           /api/v1/api-keys/:id/revoke                 # Revoke an API key
```

### Webhooks

```
POST /api/v1/webhooks/github    # Auto-compile on push (signature verified)
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Control Plane (Phoenix)            │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ LiveView │  │ REST API │  │ GitHub Webhook│  │
│  │    UI    │  │          │  │               │  │
│  └────┬─────┘  └─────┬────┘  └────────┬──────┘  │
│       │              │                │         │
│  ┌────┴──────────────┴────────────────┴───────┐ │
│  │           Contexts (Business Logic)        │ │
│  │  Bundles · Nodes · Rollouts · Audit · Auth │ │
│  └────┬──────────────┬────────────────────────┘ │
│       │              │                          │
│  ┌────┴─────┐  ┌─────┴──────┐                   │
│  │ Postgres │  │  S3/MinIO  │                   │
│  │  (state) │  │ (bundles)  │                   │
│  └──────────┘  └────────────┘                   │
└─────────────────────────────────────────────────┘
         │                          ▲
         │  Rollout assigns bundle  │  Heartbeat + status
         ▼                          │
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Zentinel   │  │  Zentinel   │  │  Zentinel   │
│   Node A    │  │   Node B    │  │   Node C    │
└─────────────┘  └─────────────┘  └─────────────┘
```

## Tech Stack

- **Elixir / Phoenix 1.8** — Web framework with LiveView for real-time UI
- **Oban** — Reliable background jobs for compilation, rollouts, monitoring, and notifications
- **Absinthe** — GraphQL API with real-time subscriptions
- **PostgreSQL** — Persistent state (SQLite for development)
- **S3 / MinIO** — Bundle artifact storage
- **Ed25519** — Bundle and JWT signing via JOSE
- **PromEx** — Prometheus metrics integration
- **OpenTelemetry** — Distributed tracing for API, Ecto, and Phoenix

## Documentation

Full documentation is available in the [`docs/`](docs/index.md) directory:

- [Getting Started](docs/getting-started.md) — Install, first project, first rollout
- [Architecture](docs/architecture.md) — System design and data flow
- [Core Concepts](docs/core-concepts.md) — Orgs, projects, bundles, nodes, rollouts
- [Configuration Management](docs/configuration-management.md) — Services, upstreams, certificates, secrets
- [Deployment & Rollouts](docs/deployment-and-rollouts.md) — Strategies, health gates, approvals
- [Security](docs/security.md) — WAF, auth policies, signing, SSO, MFA
- [Observability](docs/observability.md) — SLOs, alerts, Prometheus, OpenTelemetry
- [API Reference](docs/api-reference.md) — REST, Node, and GraphQL APIs

## Related

- [**Zentinel**](https://github.com/zentinelproxy/zentinel) — The reverse proxy this control plane manages
- [**zentinelproxy.io**](https://zentinelproxy.io) — Documentation and marketing site

## License

Apache 2.0 — See [LICENSE](LICENSE).
