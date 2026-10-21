<p align="center">
  <a href="https://zentinelproxy.io">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/zentinelproxy/design/main/marks/lockup/zentinel-lockup-dark.svg">
      <img alt="Zentinel" src="https://raw.githubusercontent.com/zentinelproxy/design/main/marks/lockup/zentinel-lockup-light.svg" height="52">
    </picture>
  </a>
</p>

<h3 align="center">Zentinel control plane</h3>

<p align="center">Fleet management for Zentinel proxies: compile KDL into signed bundles and roll them out to nodes in safe batches.</p>

<p align="center">
  <a href="https://github.com/zentinelproxy/zentinel-control-plane/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/zentinelproxy/zentinel-control-plane/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Elixir" src="https://img.shields.io/badge/elixir-1.15%2B-f68d31?style=flat&labelColor=1f161e&logo=elixir&logoColor=white">
</p>

<p align="center">
  <a href="docs/GETTING-STARTED.md">Getting started</a> &middot;
  <a href="https://docs.zentinelproxy.io">Docs</a> &middot;
  <a href="https://github.com/zentinelproxy">All repositories</a>
</p>

The control plane manages a fleet of [Zentinel](https://github.com/zentinelproxy/zentinel)
proxies from one place. It validates a KDL configuration, compiles it into an
immutable, signed bundle, and rolls that bundle out to nodes selected by label,
in batches with health gates, pause, resume and rollback. Every mutation is
audit-logged. It is an Elixir/Phoenix application with a LiveView UI, a REST
API and a GraphQL API.

<p align="center">
  <img src="priv/static/images/dashboard-screenshot.png" alt="Zentinel control plane dashboard" width="800">
</p>

## Status

**Beta.** The core workflow (compile config, create bundle, roll out to nodes)
works end to end. Multi-tenancy, audit logging, drift detection, approval
workflows and the LiveView UI are implemented and being hardened.

"End to end" means end to end *on the control-plane side*. The
[zentinel proxy](https://github.com/zentinelproxy/zentinel) does not yet ship a
control-plane client: there are no `control_plane_url`, `node_id` or `node_key`
settings in its configuration, and a stock proxy will not register, send
heartbeats or pull bundles on its own. Connecting real proxies today needs an
external sidecar that speaks the node API (the same API the built-in node
simulator uses). [PROXY-REGISTRATION.md](docs/PROXY-REGISTRATION.md) describes
what that involves.

## Quick start

Docker Compose starts the control plane, PostgreSQL and MinIO, and runs the
database migrations on start:

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane
docker compose up
```

The UI is served at [localhost:4000](http://localhost:4000), the MinIO console
at [localhost:9001](http://localhost:9001) (`minioadmin` / `minioadmin`).
Default credentials and the first rollout are covered in
[GETTING-STARTED.md](docs/GETTING-STARTED.md).

For local development with hot reloading and SQLite (no external database):

```bash
mise install        # Erlang/OTP 28.3.1 and Elixir 1.19.5, pinned in mise.toml
mise run setup      # deps, database, seeds, assets
mise run dev        # iex -S mix phx.server
```

Bundle compilation shells out to `zentinel validate --config <file>`, so a
`zentinel` binary on `PATH` is needed to compile real bundles; MinIO for local
development starts with `mise run dev:services` (Docker).

## How it works

```
KDL config → validate & compile → signed, immutable bundle → rollout → nodes pull & activate
```

1. **Upload** a KDL configuration; it is validated with `zentinel validate`.
2. **Compile** it into an immutable bundle (tar.zst with manifest, checksums
   and a CycloneDX SBOM), signed with Ed25519.
3. **Create a rollout** that targets nodes by label selector.
4. **Orchestrate** the batched deployment: health gates, progress deadlines,
   pause, resume, rollback.
5. **Nodes pull** the bundle, verify the signature, stage and activate it
   (through the node API; see [Status](#status)).

```
┌─────────────────────────────────────────────────┐
│              Control plane (Phoenix)            │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ LiveView │  │ REST API │  │ GitHub webhook│  │
│  │    UI    │  │ GraphQL  │  │               │  │
│  └────┬─────┘  └─────┬────┘  └────────┬──────┘  │
│       │              │                │         │
│  ┌────┴──────────────┴────────────────┴───────┐ │
│  │           Contexts (business logic)        │ │
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
│   node A    │  │   node B    │  │   node C    │
└─────────────┘  └─────────────┘  └─────────────┘
```

Background work (compilation, rollouts, monitoring, notifications) runs on
Oban. State lives in PostgreSQL (SQLite in development), bundle artifacts in
S3-compatible storage.

## Features

| Feature | What it does |
|---|---|
| Bundles | Immutable, content-addressed config artifacts with deterministic SHA-256 hashes |
| Bundle signing | Ed25519 signatures that nodes verify before activating |
| SBOM | A CycloneDX 1.5 SBOM for every bundle |
| Rolling deployments | Batched rollouts with batch size, health gates and progress deadlines |
| Scheduled rollouts | Rollouts scheduled for later, with a calendar view |
| Approvals | Rollouts that wait for approval, with an audit trail |
| Rollout templates | Reusable rollout settings |
| Drift detection | Flags nodes whose reported config differs from the expected bundle |
| Nodes and node groups | Registration, heartbeats, label-based targeting and groups, stale detection |
| Environments | A promotion pipeline (dev → staging → prod) with bundle tracking |
| Multi-tenancy | Organizations, projects and scoped API keys with RBAC |
| GitOps | GitHub webhook that compiles a bundle on push |
| Audit log | Every mutation logged with actor, action and diff |
| SLOs and alerting | SLOs with error budgets and burn-rate alerts; threshold and anomaly rules with silencing |
| WAF policies | About 60 built-in OWASP CRS-derived rules, policies with overrides, analytics |
| SSO and MFA | OIDC (with PKCE) and SAML 2.0 with JIT provisioning and group mapping; TOTP with recovery codes |
| Notifications | Slack, PagerDuty, Teams, email and webhook channels with routing rules |
| Service topology | A graph of services, upstreams, middlewares and policies |
| GraphQL API | Absinthe, with subscriptions |
| Developer portal | API docs generated from OpenAPI specs imported per project |
| Observability | Prometheus metrics (PromEx), OpenTelemetry tracing, JSON logs |
| Node simulator | A built-in fleet simulator for exercising rollout logic without real nodes |

## API

Interactive API documentation (Scalar) is served at
[`/api/docs`](http://localhost:4000/api/docs). The full reference is
[API.md](docs/API.md).

Node API: nodes authenticate with registration keys or JWTs.

```
POST /api/v1/projects/:slug/nodes/register   # register a node
POST /api/v1/nodes/:id/heartbeat             # send a heartbeat
GET  /api/v1/nodes/:id/bundles/latest        # fetch the latest bundle
POST /api/v1/nodes/:id/token                 # refresh the JWT
```

Control-plane API: scoped API keys (`nodes:read`, `bundles:write`,
`rollouts:write`, ...).

```
# Bundles
GET/POST  /api/v1/projects/:slug/bundles               # list / create
GET       /api/v1/projects/:slug/bundles/:id/download  # download the artifact
GET       /api/v1/projects/:slug/bundles/:id/sbom      # CycloneDX SBOM
POST      /api/v1/projects/:slug/bundles/:id/revoke    # revoke a bundle

# Rollouts
GET/POST  /api/v1/projects/:slug/rollouts              # list / create
POST      /api/v1/projects/:slug/rollouts/:id/pause
POST      /api/v1/projects/:slug/rollouts/:id/resume
POST      /api/v1/projects/:slug/rollouts/:id/rollback

# Nodes and drift
GET       /api/v1/projects/:slug/nodes
GET       /api/v1/projects/:slug/nodes/stats
GET       /api/v1/projects/:slug/drift
GET       /api/v1/projects/:slug/drift/stats
POST      /api/v1/projects/:slug/drift/:id/resolve

# API keys (api_keys:admin scope)
GET/POST  /api/v1/api-keys
POST      /api/v1/api-keys/:id/revoke

# Webhooks
POST      /api/v1/webhooks/github                      # compile on push (signature verified)

# GraphQL
POST      /api/v1/graphql
```

## Development

Toolchain: Erlang/OTP 28.3.1 and Elixir 1.19.5 (pinned in `mise.toml`, and the
versions CI and the container image use); `mix.exs` requires Elixir `~> 1.15`.

```bash
mise run dev              # interactive dev server (iex -S mix phx.server)
mise run dev:up           # start MinIO, then the dev server
mise run test             # test suite
mise run test:coverage    # tests with coverage
mise run check            # format check, credo --strict, tests
mise run lint             # credo --strict
mise run format           # mix format
mise run dialyzer         # Dialyzer
mise run db:reset         # drop, create, migrate, seed
mise run db:migrate       # pending migrations
mise run routes           # list routes
mise run docker:build     # build the image (zentinel-cp)
```

CI (`.github/workflows/ci.yml`) splits the suite with `mix test.unit`,
`mix test.integration` and `mix test.e2e`, and runs `mix format
--check-formatted`, `mix credo`, `mix deps.audit` and `mix hex.audit`.
`publish.yml` builds and publishes the container image on pushes to `main`.

## Documentation

The [`docs/`](docs/README.md) directory:

- [GETTING-STARTED.md](docs/GETTING-STARTED.md): install, default credentials, first project, first rollout
- [ARCHITECTURE.md](docs/ARCHITECTURE.md): components, data flow, background jobs
- [API.md](docs/API.md): REST, node and GraphQL APIs, with curl examples
- [AUTHENTICATION.md](docs/AUTHENTICATION.md): sessions, API keys, node auth, SSO, MFA, roles
- [CONFIGURATION.md](docs/CONFIGURATION.md): services, upstreams, TLS, middlewares, environment variables
- [DEPLOYMENT.md](docs/DEPLOYMENT.md): Docker, production setup, rollout strategies, health gates
- [SECURITY.md](docs/SECURITY.md): WAF, auth policies, bundle signing, encryption at rest
- [OBSERVABILITY.md](docs/OBSERVABILITY.md): Prometheus, SLOs, alerts, tracing, drift, notifications
- [PROXY-REGISTRATION.md](docs/PROXY-REGISTRATION.md): connecting proxies through the node API
- [DEVELOPMENT.md](docs/DEVELOPMENT.md): working on the control plane

## Related

- [Zentinel](https://github.com/zentinelproxy/zentinel): the proxy this control plane manages
- [Zentinel docs](https://docs.zentinelproxy.io): proxy configuration reference
- [zentinel-hub](https://github.com/zentinelproxy/zentinel-hub): the earlier Go control plane, superseded by this repository

## License

This repository has no `LICENSE` file yet.

---

<p align="center">
  <sub>Part of <a href="https://zentinelproxy.io">Zentinel</a>, the security-first reverse proxy. The shisa guards the gate.</sub>
</p>
