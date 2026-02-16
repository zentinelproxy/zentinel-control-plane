# Architecture

This document describes the system architecture of Sentinel Control Plane, including component interactions, data flow, and deployment topology.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane (Phoenix)                   │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  REST API   │  LiveView   │   Compiler  │  Rollout Engine  │
│             │     UI      │   Service   │     (Oban)       │
├─────────────┴─────────────┴─────────────┴──────────────────┤
│   Events & Notifications  │  Observability  │  Analytics    │
│   (Webhooks, Slack, etc.) │  (SLOs, Alerts) │  (Metrics)    │
└──────┬──────┬─────────────┴───────┬─────┴────────┬─────────┘
       │      │                     │              │
       │      │  ┌──────────────────┘              │
       │      │  │                                 │
       │   ┌──┴──┴───────┐              ┌─────────┴──────────┐
       │   │  PostgreSQL  │              │    MinIO / S3      │
       │   │  (SQLite dev)│              │  (Bundle Storage)  │
       │   └──────────────┘              └────────────────────┘
       │
┌──────┴──────────────────────────────────────────────────────┐
│                      Sentinel Nodes                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Node 1  │  │ Node 2  │  │ Node 3  │  │ Node N  │  ...   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### REST API

The API layer provides endpoints for three distinct consumers:

- **Operator API** — Authenticated with API keys, used by operators and CI/CD pipelines to manage bundles, rollouts, services, and other resources. All endpoints are scoped under `/api/v1/projects/:project_slug/`.
- **Node API** — Authenticated with node keys or JWT tokens, used by Sentinel proxy nodes for registration, heartbeats, bundle polling, metrics ingestion, and event reporting.
- **Webhook API** — Signature-verified endpoints for GitOps integrations (GitHub, GitLab, Bitbucket, Gitea, and generic webhooks).

See [API Reference](api-reference.md) for endpoint details.

### LiveView UI

A real-time web interface built with Phoenix LiveView. The UI provides dashboards, resource management forms, and live-updating views for rollout progress, node health, drift detection, alerts, and analytics. All browser routes are org-scoped (`/orgs/:org_slug/projects/:project_slug/...`).

### Compiler Service

The compiler validates and assembles configuration bundles:

1. **Validation** — Runs `sentinel validate` against the KDL configuration source
2. **Assembly** — Creates a `.tar.zst` archive containing the configuration, manifest, internal CA certificates, and plugin files
3. **Storage** — Uploads the archive to S3-compatible storage
4. **Signing** — Optionally signs the bundle with Ed25519 keys
5. **Risk Scoring** — Compares against the previous bundle to flag auth, TLS, or rate limit changes

Compilation runs as an Oban background job (`CompileWorker`).

### Rollout Engine

The rollout engine orchestrates safe deployment of bundles to node fleets:

- Runs as a self-rescheduling Oban worker (`TickWorker`) that ticks every 5 seconds
- Supports four strategies: rolling, canary, blue-green, and all-at-once
- Evaluates health gates between batches (heartbeat status, error rate, latency, CPU, memory)
- Integrates with the approval workflow, freeze windows, and auto-rollback

See [Deployment & Rollouts](deployment-and-rollouts.md) for details.

### Events & Notifications

A pub/sub event system that routes operational events to notification channels:

- **Event types**: rollout state changes, bundle promotions, drift detection, security alerts, WAF anomalies
- **Channels**: Slack, PagerDuty, Microsoft Teams, email, generic webhooks
- **Routing**: Pattern-based notification rules (e.g., `rollout.*`, `security.*`)
- **Delivery**: Reliable delivery with exponential backoff retries and dead-letter queue

See [Integrations > Notifications](integrations.md#notification-channels) for setup.

### Observability

Built-in monitoring and alerting:

- **SLOs/SLIs** — Define availability, latency, and error rate targets with error budget tracking
- **Alert Rules** — Metric-based and SLO burn-rate alerts with configurable severity and grace periods
- **Service Metrics** — Request counts, latency percentiles, error rates, and bandwidth aggregated per service
- **Metric Rollups** — Automatic hourly and daily aggregation with configurable retention

See [Observability](observability.md) for details.

### Analytics

Request-level analytics and security event processing:

- **Request Logs** — Per-request records with method, path, status, latency, and client info
- **WAF Events** — Security events from WAF rule matches across the fleet
- **WAF Baselines** — Statistical baselines computed over 14-day rolling windows
- **Anomaly Detection** — Z-score analysis to detect spikes, new attack vectors, and IP bursts

## Data Flow

### Bundle Deployment Flow

```
Operator creates bundle
        │
        ▼
  CompileWorker (Oban)
   ├─ Validate KDL config
   ├─ Assemble .tar.zst archive
   ├─ Upload to S3/MinIO
   ├─ Sign with Ed25519 (optional)
   └─ Score risk vs. previous bundle
        │
        ▼
  Bundle status: "compiled"
        │
        ▼
  Operator creates rollout
        │
        ▼
  Approval workflow (if required)
        │
        ▼
  Plan rollout → create batched steps
        │
        ▼
  TickWorker (every 5s)
   ├─ Deploy batch to nodes (set staged_bundle_id)
   ├─ Wait for nodes to activate
   ├─ Verify health gates
   └─ Advance to next batch or complete
        │
        ▼
  Nodes poll for updates
   ├─ GET /api/v1/nodes/:id/bundles/latest
   ├─ Download bundle from presigned S3 URL
   ├─ Apply configuration
   └─ Report activation via heartbeat
```

### Node Communication Flow

Sentinel nodes interact with the control plane through a pull-based model:

```
Node Registration (once)
   POST /api/v1/projects/:slug/nodes/register
   ← Returns: node_id, node_key
        │
        ▼
Periodic Heartbeat (every 10-30s)
   POST /api/v1/nodes/:id/heartbeat
   → Sends: health, metrics, active_bundle_id
   ← Returns: expected_bundle_id (if different)
        │
        ▼
Bundle Polling (every 5-30s)
   GET /api/v1/nodes/:id/bundles/latest
   ← Returns: bundle metadata + presigned download URL
        │
        ▼
Metrics Push (periodic)
   POST /api/v1/nodes/:id/metrics
   → Sends: request counts, latencies, status codes
        │
        ▼
WAF Events Push (periodic)
   POST /api/v1/nodes/:id/waf-events
   → Sends: rule matches, blocked requests, client IPs
```

## Multi-Tenancy

The control plane uses a hierarchical multi-tenancy model:

```
Organization (Org)
├── Members (users with roles: admin, operator, reader)
├── Signing Keys (Ed25519 key pairs for JWT)
├── SSO Providers (OIDC, SAML)
└── Projects
    ├── Environments (dev, staging, production)
    ├── Nodes (proxy instances)
    ├── Bundles (configuration artifacts)
    ├── Rollouts (deployment plans)
    ├── Services (proxy route definitions)
    ├── Secrets, Certificates, Plugins, etc.
    ├── Notification Channels & Rules
    ├── SLOs, Alert Rules
    └── Audit Logs
```

All resources are scoped to a project, which belongs to an organization. API keys can optionally be scoped to a specific project for isolation. Audit logs capture both the project and org context.

See [Core Concepts](core-concepts.md) for details on each resource type.

## Database

- **Development/Test**: SQLite — zero configuration, selected at compile time
- **Production**: PostgreSQL — selected via `config :sentinel_cp, :ecto_adapter`

The adapter choice is transparent to application code through Ecto's abstraction layer.

## Storage

Bundle artifacts are stored in S3-compatible object storage:

- **Development**: MinIO (local S3-compatible server) or local filesystem (`priv/bundles`)
- **Production**: AWS S3 or any S3-compatible service

Storage paths follow the pattern: `bundles/{project_id}/{bundle_id}.tar.zst`

## Background Jobs

The control plane uses [Oban](https://hexdocs.pm/oban/) for reliable background processing:

| Worker | Schedule | Purpose |
|--------|----------|---------|
| `CompileWorker` | On demand | Bundle validation, assembly, signing |
| `RolloutTickWorker` | Every 5s (per rollout) | Advance rollout state machine |
| `StalenessWorker` | Periodic | Mark nodes offline after 120s without heartbeat |
| `GCWorker` | Periodic | Clean up old bundles |
| `DriftWorker` | Every 30s | Detect and remediate configuration drift |
| `SliWorker` | Every 5 min | Compute SLI values for all SLOs |
| `AlertEvaluator` | Every 30s | Evaluate alert rule conditions |
| `RollupWorker` | Every hour | Aggregate metrics into hourly/daily rollups |
| `WafBaselineWorker` | Every hour | Compute WAF statistical baselines |
| `WafAnomalyWorker` | Every 15 min | Detect WAF anomalies |

## Observability Stack

```
Sentinel Nodes ──metrics──▶ Control Plane ──▶ Service Metrics DB
                                            ──▶ Prometheus (PromEx)
                                            ──▶ OpenTelemetry (traces)
                                            ──▶ Alert Evaluator
                                            ──▶ SLI Computer
```

The control plane exposes Prometheus metrics at `/metrics` via PromEx, including BEAM VM metrics, Phoenix HTTP metrics, Ecto query metrics, Oban job metrics, and custom Sentinel metrics (node counts, drift events, SLO status, active rollouts).

OpenTelemetry tracing wraps key operations: bundle compilation, rollout ticks, webhook processing, and node heartbeats.
