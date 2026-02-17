# Zentinel Control Plane - Development Guide

## Overview

Zentinel CP is a fleet management control plane for Zentinel reverse proxies, built in Elixir/Phoenix. It provides:

- Bundle compilation and distribution
- Safe rollout orchestration with health gates
- Node lifecycle management
- Audit logging and observability

## Quick Start

```bash
# Install dependencies
mise install
mise run setup

# Start development server
mise run dev

# Run tests
mise run test
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane (Phoenix)                   │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  REST API   │  LiveView   │   Compiler  │  Rollout Engine  │
│             │     UI      │   Service   │     (Oban)       │
└──────┬──────┴──────┬──────┴──────┬──────┴────────┬─────────┘
       │             │             │               │
       │     ┌───────┴───────┐    │               │
       │     │   PostgreSQL  │    │               │
       │     │   (SQLite dev)│    │               │
       │     └───────────────┘    │               │
       │                          │               │
       │              ┌───────────┴───────────────┤
       │              │      MinIO / S3           │
       │              │   (Bundle Storage)        │
       │              └───────────────────────────┘
       │
┌──────┴──────────────────────────────────────────────────────┐
│                      Zentinel Nodes                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Node 1  │  │ Node 2  │  │ Node 3  │  │ Node N  │  ...   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
lib/
├── zentinel_cp/
│   ├── accounts/       # Users, API keys, authentication
│   ├── audit/          # Audit logging
│   ├── auth/           # JWT signing keys, node tokens (Ed25519)
│   ├── bundles/        # Bundle lifecycle, compiler, signing, SBOM, diff
│   ├── dashboard/      # Fleet overview and metrics aggregation
│   ├── nodes/          # Node management, heartbeats
│   ├── orgs/           # Multi-org support, memberships
│   ├── projects/       # Project/tenant management
│   ├── prom_ex/        # Prometheus metrics (custom Zentinel plugin)
│   ├── rollouts/       # Rollout orchestration, tick worker, health gates
│   ├── simulator/      # Node simulator (GenServer fleet)
│   └── webhooks/       # GitHub webhook integration (GitOps)
└── zentinel_cp_web/
    ├── controllers/    # REST API + webhook endpoints
    ├── live/           # LiveView pages (dashboard, nodes, bundles, rollouts, audit, orgs)
    ├── plugs/          # Auth, API auth, node auth, scope checking, org scoping
    └── components/     # UI components
```

## Key Concepts

### Bundles
Immutable, content-addressed configuration artifacts:
- Validated via `zentinel validate`
- Compressed as `.tar.zst`
- Stored in S3/MinIO
- Identified by SHA256 hash

### Rollouts
Safe deployment plans:
- Batch-based progression
- Health gates between steps
- Automatic pause on failure
- Manual rollback support

### Nodes
Zentinel proxy instances:
- Pull-based bundle distribution
- Heartbeat-based health tracking
- Per-node status during rollouts

## Database

- **Development/Test**: SQLite (zero configuration)
- **Production**: PostgreSQL

The adapter is selected at compile time via `config :zentinel_cp, :ecto_adapter`.

## Background Jobs

Using Oban for reliable job processing:
- `CompileWorker`: Validates, assembles, signs, and uploads bundles
- `RolloutTickWorker`: Advances rollout state (self-rescheduling every 5s)
- `StalenessWorker`: Marks offline nodes (120s threshold)
- `GCWorker`: Cleans old bundles

## Development

### Running Tests
```bash
mise run test           # Full suite
mise run test:coverage  # With coverage
```

### Code Quality
```bash
mise run format         # Format code
mise run lint           # Run Credo
mise run check          # Format + lint + test
```

### Database
```bash
mise run db:setup       # Create + migrate
mise run db:reset       # Drop + create + migrate
mise run db:migrate     # Run migrations
```

## Implementation Status

See [CONTROL_PLANE_ROADMAP.md](./CONTROL_PLANE_ROADMAP.md) for the original roadmap.

All phases (1-7) and v1.1 features are implemented.

## Work Instructions

When implementing features:

1. **Write tests first** - Especially for domain logic
2. **Use contexts** - Keep Phoenix conventions
3. **Audit mutations** - Log all state changes
4. **Handle errors explicitly** - No silent failures

### Code Style

- Use `with` for happy-path pipelines
- Use `TypedStruct` for complex structs
- Prefer explicit function heads over guards
- Keep LiveViews thin - delegate to contexts

### Naming Conventions

- Contexts: `ZentinelCp.Nodes`, `ZentinelCp.Bundles`, `ZentinelCp.Orgs`
- Schemas: `ZentinelCp.Nodes.Node`, `ZentinelCp.Bundles.Bundle`, `ZentinelCp.Orgs.Org`
- Workers: `ZentinelCp.Rollouts.TickWorker`, `ZentinelCp.Bundles.CompileWorker`
- LiveViews: `ZentinelCpWeb.NodesLive.Index`, `ZentinelCpWeb.DashboardLive.Index`
- Plugs: `ZentinelCpWeb.Plugs.Auth`, `ZentinelCpWeb.Plugs.NodeAuth`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection (prod) | Required in prod |
| `SECRET_KEY_BASE` | Phoenix secret | Required in prod |
| `PHX_HOST` | Public hostname | `localhost` |
| `PORT` | HTTP port | `4000` |
| `S3_BUCKET` | Bundle storage bucket | `zentinel-bundles` |
| `S3_ENDPOINT` | S3/MinIO endpoint | `http://localhost:9000` |
| `S3_ACCESS_KEY_ID` | S3 access key | - |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | - |
| `ZENTINEL_BINARY` | Path to `zentinel` CLI binary | `zentinel` |
| `GITHUB_WEBHOOK_SECRET` | HMAC secret for GitHub webhooks | - |
