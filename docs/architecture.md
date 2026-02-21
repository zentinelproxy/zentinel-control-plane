# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane (Phoenix)                   │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  REST API   │  LiveView   │  Compiler   │  Rollout Engine  │
│  (JSON)     │  UI (WS)    │  (Oban)     │  (Oban, 5s tick) │
├─────────────┴─────────────┴─────────────┴──────────────────┤
│  Events & Notifications  │  Observability  │  Analytics     │
│  (Slack, PD, Teams, WH)  │  (SLOs, Alerts) │  (WAF, Reqs)  │
└──────┬──────┬─────────────┴───────┬─────┴────────┬─────────┘
       │      │                     │              │
       │   ┌──┴─────────────┐   ┌──┴──────────────┘
       │   │  PostgreSQL     │   │  MinIO / S3
       │   │  (SQLite dev)   │   │  (Bundle Storage)
       │   └─────────────────┘   └────────────────────
       │
┌──────┴──────────────────────────────────────────────────────┐
│                      Zentinel Nodes                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Node 1  │  │ Node 2  │  │ Node 3  │  │ Node N  │  ...   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### REST API

Three consumer classes, same Phoenix router:

| Consumer | Auth Method | Base Path | Purpose |
|----------|-------------|-----------|---------|
| **Operator** | API key (`Authorization: Bearer`) | `/api/v1/projects/:slug/` | Manage bundles, rollouts, services, nodes |
| **Node** | Node key / JWT | `/api/v1/nodes/:id/` | Registration, heartbeats, bundle polling, metrics |
| **Webhook** | HMAC signature | `/api/v1/webhooks/` | GitOps triggers (GitHub, GitLab, Bitbucket, Gitea) |

Plug pipeline: `ZentinelCpWeb.Plugs.ApiAuth` (operator), `ZentinelCpWeb.Plugs.NodeAuth` (node), `ZentinelCpWeb.Plugs.RequireScope` (scope enforcement), `ZentinelCpWeb.Plugs.RateLimit` (token bucket).

### LiveView UI

Real-time web interface via Phoenix LiveView over WebSocket. All browser routes are org-scoped: `/orgs/:org_slug/projects/:project_slug/...`.

Key pages: dashboard (fleet overview), nodes (list/detail), bundles (management + diff viewer), rollouts (live tracking), services (editor), topology (service graph), WAF dashboard, SLOs, alerts, notifications, drift events, audit log.

### Compiler Service

Runs as `ZentinelCp.Bundles.CompileWorker` (Oban background job):

```
KDL source → validate (zentinel CLI) → assemble .tar.zst → upload to S3
                                      → sign with Ed25519 (optional)
                                      → generate CycloneDX 1.5 SBOM
                                      → score risk vs. previous bundle
```

Risk scoring flags: auth policy changes → high, TLS changes → high, upstream removals → medium, rate limit changes → medium, >10 route changes → medium.

### Rollout Engine

Self-rescheduling Oban worker (`ZentinelCp.Rollouts.TickWorker`), ticks every 5 seconds per active rollout.

| Strategy | Behavior |
|----------|----------|
| `rolling` | Fixed-size batches, health gate checks between each |
| `canary` | Progressive traffic ramp (5% → 25% → 50% → 100%), statistical analysis |
| `blue_green` | Deploy to standby slot, shift traffic, validate, swap |
| `all_at_once` | All target nodes simultaneously |

Health gates evaluated between batches: heartbeat status, error rate, P99 latency, CPU%, memory%. Custom health check endpoints per project.

Supporting workers: `SchedulerWorker` (scheduled rollouts), `HealthChecker` (gate evaluation), `CanaryAnalysis` (statistical comparison).

### Events & Notifications

Pub/sub event system routing operational events to channels:

- **Event types**: `rollout.*`, `bundle.*`, `drift.*`, `security.*`, `waf.*`
- **Channels**: Slack, PagerDuty, Microsoft Teams, email (Swoosh), generic webhooks
- **Routing**: Pattern-based notification rules
- **Delivery**: Exponential backoff retries, dead-letter queue

### Observability

| Component | Implementation |
|-----------|---------------|
| SLOs/SLIs | Availability, latency, error rate targets. `SliWorker` computes every 5 min |
| Alert Rules | Metric-based + SLO burn-rate. `AlertEvaluator` runs every 30s |
| Service Metrics | Per-service request counts, latency percentiles, error rates, bandwidth |
| Metric Rollups | Hourly/daily aggregation via `RollupWorker` |
| Prometheus | `GET /metrics` via PromEx (BEAM, Phoenix, Ecto, Oban, custom) |
| OpenTelemetry | Batch span processor, configurable OTLP exporter |

### Analytics

- **Request logs**: Per-request records — method, path, status, latency, client info
- **WAF events**: Rule matches across the fleet per node
- **WAF baselines**: 14-day rolling windows, computed hourly
- **Anomaly detection**: Z-score analysis (>2.5σ) — spikes, new attack vectors, IP bursts

## Data Flow

### Bundle Deployment

```
Operator creates bundle
        │
        ▼
  CompileWorker (Oban)
   ├─ zentinel validate (KDL)
   ├─ Assemble .tar.zst
   ├─ Upload to S3/MinIO
   ├─ Sign with Ed25519 (optional)
   └─ Score risk vs. previous
        │
        ▼
  Bundle status: "compiled"
        │
        ▼
  Operator creates rollout
        │
        ▼
  Approval workflow (if configured)
        │
        ▼
  TickWorker (every 5s)
   ├─ Create batched steps
   ├─ Set staged_bundle_id on batch nodes
   ├─ Wait for node activation
   ├─ Verify health gates
   └─ Advance to next batch or complete
        │
        ▼
  Nodes poll → download from S3 → activate → report via heartbeat
```

### Node Communication

Pull-based model. Nodes initiate all communication.

```
Registration (once):
  POST /api/v1/projects/:slug/nodes/register
  ← {node_id, node_key, poll_interval_s}

Heartbeat (every 10-30s):
  POST /api/v1/nodes/:id/heartbeat
  → {health, metrics, active_bundle_id, staged_bundle_id}

Bundle polling (every 5-30s):
  GET /api/v1/nodes/:id/bundles/latest
  ← {bundle metadata, presigned S3 URL} or 204

Token refresh (on JWT expiry):
  POST /api/v1/nodes/:id/token  [with static key]
  ← {jwt, expires_at}

Metrics push (periodic):
  POST /api/v1/nodes/:id/metrics

WAF events push (periodic):
  POST /api/v1/nodes/:id/waf-events
```

## Multi-Tenancy

```
Organization
├── Members (admin, operator, reader)
├── Signing Keys (Ed25519 for JWT issuance)
├── SSO Providers (OIDC, SAML)
└── Projects
    ├── Environments (dev → staging → production)
    ├── Nodes
    ├── Bundles
    ├── Rollouts
    ├── Services, Upstream Groups, Certificates
    ├── Auth Policies, WAF Policies, Middlewares
    ├── Plugins, Secrets
    ├── Notification Channels & Rules
    ├── SLOs, Alert Rules
    └── Audit Logs
```

All resources scoped to project → organization. API keys optionally scoped to a project.

## Database

| Environment | Adapter | Config |
|-------------|---------|--------|
| Dev/Test | `Ecto.Adapters.SQLite3` | Zero config, file-based |
| Production | `Ecto.Adapters.Postgres` | `DATABASE_URL` env var |

Selected at compile time via `config :zentinel_cp, :ecto_adapter`. Transparent to application code through Ecto.

## Storage

Bundle artifacts in S3-compatible object storage:

- **Path**: `bundles/{project_id}/{bundle_id}.tar.zst`
- **Dev**: MinIO at `localhost:9000`
- **Prod**: AWS S3 or compatible
- **Download**: Presigned URLs (no proxy through control plane)

## Background Jobs

Oban queues: `default` (10 workers), `rollouts` (5), `maintenance` (2).

| Worker | Schedule | Purpose |
|--------|----------|---------|
| `CompileWorker` | On demand | Bundle validation, assembly, signing, upload |
| `RolloutTickWorker` | Every 5s (per rollout) | Advance rollout state machine |
| `SchedulerWorker` | Periodic | Trigger scheduled rollouts |
| `StalenessWorker` | Periodic | Mark nodes offline after 120s |
| `GCWorker` | Periodic | Clean up old/revoked bundles |
| `DriftWorker` | Every 30s | Detect config drift, optional auto-remediation |
| `SliWorker` | Every 5 min | Compute SLI values for SLOs |
| `AlertEvaluator` | Every 30s | Evaluate alert rule conditions |
| `RollupWorker` | Every hour | Aggregate metrics into hourly/daily rollups |
| `WafBaselineWorker` | Every hour | Compute WAF statistical baselines |
| `WafAnomalyWorker` | Every 15 min | Z-score anomaly detection |

## Observability Stack

```
Zentinel Nodes ──metrics/waf──▶ Control Plane ──▶ Service Metrics (DB)
                                               ──▶ GET /metrics (PromEx)
                                               ──▶ OTLP exporter (traces)
                                               ──▶ AlertEvaluator → Notifications
                                               ──▶ SliWorker → Error Budgets
```

PromEx exposes: BEAM VM, Phoenix requests, Ecto queries, Oban jobs, plus custom Zentinel metrics (node counts, drift events, SLO status, active rollouts, bundle sizes).

OpenTelemetry wraps: bundle compilation, rollout ticks, webhook processing, node heartbeats.
