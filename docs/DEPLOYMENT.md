# Deployment

## Docker

### docker-compose.yml

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| `app` | Built from Dockerfile | 4000 | Control plane |
| `postgres` | `postgres:17` | 5432 | Database |
| `minio` | `minio/minio` | 9000 (API), 9001 (console) | Bundle storage |
| `minio-init` | `minio/mc` | — | Creates `zentinel-bundles` bucket |

### Dockerfile

Multi-stage build:

1. **Build stage**: `hexpm/elixir:1.19.5-erlang-28.3.1-debian-bookworm-20260202-slim`
   - Compiles Elixir dependencies
   - Builds assets with esbuild + Tailwind
   - Creates OTP release
2. **Runtime stage**: Slim Debian image
   - Runs as non-root user `zentinel`
   - Healthcheck: `curl http://localhost:4000/health`
   - Startup: runs migrations via `ZentinelCp.Release.migrate()`, then starts with `PHX_SERVER=true`

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Prod | — | `ecto://user:pass@host:5432/db` |
| `SECRET_KEY_BASE` | Prod | — | Phoenix secret (generate: `mix phx.gen.secret`) |
| `PHX_HOST` | Prod | `localhost` | Public hostname for URL generation |
| `PORT` | No | `4000` | HTTP listen port |
| `S3_ENDPOINT` | Yes | `http://localhost:9000` | S3/MinIO endpoint |
| `S3_BUCKET` | Yes | `zentinel-bundles` | Storage bucket name |
| `S3_ACCESS_KEY_ID` | Yes | — | S3 access key |
| `S3_SECRET_ACCESS_KEY` | Yes | — | S3 secret key |
| `S3_REGION` | No | `us-east-1` | S3 region |
| `ZENTINEL_BINARY` | No | `zentinel` | Path to `zentinel` CLI |
| `GITHUB_WEBHOOK_SECRET` | No | — | HMAC secret for GitHub webhooks |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | — | OpenTelemetry collector |
| `FORCE_SSL` | No | `false` | `true` to redirect HTTP → HTTPS |
| `POOL_SIZE` | No | `10` | Database connection pool size |

### Production Checklist

- [ ] Generate a unique `SECRET_KEY_BASE` (`mix phx.gen.secret`)
- [ ] Change default admin password (`admin@localhost` / `changeme123456`)
- [ ] Use a managed PostgreSQL instance
- [ ] Configure S3 (AWS or compatible) with proper IAM credentials
- [ ] Set `PHX_HOST` to your public domain
- [ ] Set `FORCE_SSL=true` and terminate TLS at load balancer or proxy
- [ ] Tune `POOL_SIZE` for expected load
- [ ] Configure backup strategy for PostgreSQL
- [ ] Set up monitoring (scrape `GET /metrics`)

### Startup Flow

```
docker compose up
  │
  ├─ PostgreSQL initializes (user: zentinel, db: zentinel_cp)
  ├─ MinIO starts, minio-init creates bucket
  ├─ App waits for pg_isready
  ├─ App runs ZentinelCp.Release.migrate()
  ├─ Database seeded (default org + admin user)
  └─ Phoenix server starts on :4000
```

## Rollout Strategies

### Rolling (Default)

Deploy in fixed-size batches with health gate checks between each batch.

```json
{
  "strategy": "rolling",
  "batch_size": 2,
  "health_gates": {"heartbeat_healthy": true, "max_error_rate": 5.0}
}
```

Progression: batch 1 → health check → batch 2 → health check → ... → complete.

### Canary

Gradually increase traffic to the new bundle with statistical analysis:

```json
{
  "strategy": "canary",
  "canary_steps": [5, 25, 50, 100],
  "health_gates": {"heartbeat_healthy": true, "max_error_rate": 2.0}
}
```

Progression: 5% traffic → analyze → 25% → analyze → 50% → analyze → 100%.

Use `POST /rollouts/:id/advance-traffic` for manual canary advancement.

### Blue-Green

Deploy to standby slot, shift traffic, validate, then swap:

```json
{
  "strategy": "blue_green",
  "health_gates": {"heartbeat_healthy": true}
}
```

1. Deploy new bundle to "green" slot (all target nodes)
2. Shift traffic incrementally
3. Validate health
4. `POST /rollouts/:id/swap-slot` to finalize

### All at Once

Deploy to all target nodes simultaneously:

```json
{
  "strategy": "all_at_once",
  "health_gates": {"heartbeat_healthy": true}
}
```

No batching. All nodes receive the new bundle at once.

## Health Gates

Evaluated between rollout batches:

| Gate | Type | Description |
|------|------|-------------|
| `heartbeat_healthy` | Boolean | All batch nodes reporting heartbeats |
| `max_error_rate` | Float (%) | Error rate stays below threshold |
| `max_latency_ms` | Integer | P99 latency stays below threshold |
| `max_cpu_percent` | Float (%) | CPU usage below threshold |
| `max_memory_percent` | Float (%) | Memory usage below threshold |

Custom health check endpoints can also be configured per project.

## Target Selectors

| Selector | JSON | Description |
|----------|------|-------------|
| All nodes | `{"type": "all"}` | Every node in the project |
| By labels | `{"type": "labels", "labels": {"env": "prod"}}` | Nodes matching labels |
| By IDs | `{"type": "node_ids", "node_ids": ["..."]}` | Specific nodes |
| By groups | `{"type": "groups", "group_ids": ["..."]}` | Nodes in groups |

## Rollout States

```
pending → running → completed
           │  ↑
           ▼  │
         paused
           │
           ▼
       cancelled / failed
```

- **Pause**: `POST /rollouts/:id/pause` — stops progression, nodes keep current state
- **Resume**: `POST /rollouts/:id/resume` — continues from where it paused
- **Cancel**: `POST /rollouts/:id/cancel` — stops, no revert
- **Rollback**: `POST /rollouts/:id/rollback` — reverts to previous bundle

## Approval Workflow

- Configurable per project and per environment
- Configurable number of required approvals (default: 1)
- Approvers cannot approve their own rollouts
- Rejection requires a comment
- Rollout auto-transitions when approval threshold met

## Freeze Windows

Time-based deployment freezes:

- Define start/end times for freeze periods
- Can be project-wide or scoped to a specific environment
- Rollout creation blocked during freeze windows
- Useful for holidays, critical business events, maintenance windows

## Scheduled Rollouts

Set `scheduled_at` (ISO 8601) when creating a rollout. The `SchedulerWorker` triggers it at the specified time, subject to freeze windows and approval requirements.
