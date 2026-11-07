# Deployment

## Docker Compose

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
| `SECRET_KEY_BASE` | Prod | — | Phoenix secret (generate: `mix phx.gen.secret`). Must be the same on all instances |
| `ENCRYPTION_KEY` | Prod | — | Encrypts secrets in the database. 32 bytes, Base64 (`openssl rand -base64 32`) |
| `ENCRYPTION_KEYS_OLD` | No | — | Comma-separated retired keys, still used to decrypt during rotation |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | First boot | — | Creates the first admin if no users exist. There is no default account |
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
| `TRUSTED_PROXY_COUNT` | Behind a proxy | `0` | Your proxies in front of the app. Needed for correct client addresses and per-address rate limits |
| `METRICS_TOKEN` | For metrics | — | Bearer token for `/metrics`. Without it, the endpoint is closed |
| `DATABASE_SSL` | Recommended | `false` | `true` to connect to PostgreSQL over verified TLS |
| `DATABASE_CA_CERT` | No | OS trust store | CA file for `DATABASE_SSL` |
| `ALLOW_PRIVATE_OUTBOUND` | No | `false` | `true` to allow webhooks and health checks to reach private and local addresses |
| `BUNDLE_SIGNING_ENABLED` | Recommended | `false` | `true` to sign bundles and audit checkpoints |
| `BUNDLE_SIGNING_KEY_ID` | No | `default` | Key ID recorded with signatures |
| `BUNDLE_SIGNING_PRIVATE_KEY_PATH` | With signing | — | File with a Base64 Ed25519 private key |
| `BUNDLE_SIGNING_PUBLIC_KEY_PATH` | With signing | — | File with a Base64 Ed25519 public key |
| `MAILER_ADAPTER` | For email | — | `postmark`, `sendgrid` or `mailgun`. Without it, email channels report a delivery error |
| `MAILER_API_KEY` | With mailer | — | Provider API key |
| `MAILER_DOMAIN` | With Mailgun | — | Sending domain |

### Production Checklist

- [ ] Generate stable `SECRET_KEY_BASE` and `ENCRYPTION_KEY` values, and back up `ENCRYPTION_KEY` separately from the database. Without it, stored secrets cannot be recovered
- [ ] Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` for first boot, then remove them
- [ ] Use a managed PostgreSQL instance with `DATABASE_SSL=true`
- [ ] Configure S3 (AWS or compatible) with credentials limited to the bucket
- [ ] Set `PHX_HOST` to your public domain
- [ ] Set `FORCE_SSL=true` and terminate TLS at a load balancer or proxy
- [ ] Set `TRUSTED_PROXY_COUNT` to the number of proxies in front of the app
- [ ] Set `METRICS_TOKEN` and configure Prometheus to send it
- [ ] Set `BUNDLE_SIGNING_ENABLED=true` with an Ed25519 key pair
- [ ] Set `MAILER_ADAPTER` if you use email notification channels
- [ ] Tune `POOL_SIZE` for expected load
- [ ] Configure backups and test a restore (see [Backup and Restore](#backup-and-restore))
- [ ] Restrict outbound network access from the app. URL checks reduce but do not remove SSRF risk
- [ ] Enable an MFA policy for each organization

### Upgrading an Existing Install

These steps apply when upgrading from a version without `ENCRYPTION_KEY`:

1. Set `ENCRYPTION_KEY`, and keep `SECRET_KEY_BASE` unchanged. Older secrets were encrypted with a key derived from it.
2. Create a registration token for each project, and give it to whatever registers new nodes. Registered nodes are not affected.
3. Rename any projects that share a slug with a project in another org. Otherwise the migration fails, because slugs are now unique across all orgs.
4. Deploy. Migrations run on startup.
5. Run `bin/zentinel_cp eval "ZentinelCp.Release.reencrypt_secrets()"`. After this, `SECRET_KEY_BASE` can be rotated.
6. If `admin@localhost` exists with the old default password, change its password or delete it. It is no longer recreated.
7. Review global admins. Earlier versions gave SSO users their mapped role globally, so an SSO user mapped to `admin` could reach every org. New SSO users are created as global `reader`, but existing ones keep their role.
8. Review API keys. A key now needs its owner to be a member of the project's org, so keys owned by non-members stop working.
9. Audit entries written before this version only have their links verified, not their contents.

### Rotating the Encryption Key

1. Set `ENCRYPTION_KEY` to a new key and add the old one to `ENCRYPTION_KEYS_OLD`.
2. Deploy to all instances.
3. Run `bin/zentinel_cp eval "ZentinelCp.Release.reencrypt_secrets()"`.
4. Remove the old key from `ENCRYPTION_KEYS_OLD`.

### Running Several Instances

- All instances need the same `SECRET_KEY_BASE` and `ENCRYPTION_KEY`.
- Rate limits are counted per instance, so the effective limit is multiplied by the instance count.
- Set `DNS_CLUSTER_QUERY` so instances join a cluster. LiveView updates need this to cross instances.
- Periodic jobs are safe to run from several instances, because they are unique in Oban.

### Backup and Restore

Back up all three of these, because each is useless without the others:

| What | How |
|------|-----|
| PostgreSQL | Managed backups with point-in-time recovery, or `pg_dump --format=custom` |
| Bundle storage | S3 versioning or bucket replication |
| `ENCRYPTION_KEY` and signing keys | A secrets manager, stored separately from database backups |

To restore:

```bash
pg_restore --clean --if-exists --no-owner --dbname "$DATABASE_URL_LIBPQ" backup.dump
bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
```

Then start the app with the original `ENCRYPTION_KEY`, and check that:

- `GET /ready` returns 200.
- `GET /api/v1/audit/verify`, with a global admin key, reports a valid chain.
- A bundle downloads, and an existing certificate or secret can still be read.

Test this regularly. A backup that has never been restored is not known to work.

### Startup Flow

```
docker compose up
  │
  ├─ PostgreSQL initializes (user: zentinel, db: zentinel_cp)
  ├─ MinIO starts, minio-init creates bucket
  ├─ App runs ZentinelCp.Release.migrate(), retrying until the database is ready
  ├─ First admin and default org created from ADMIN_EMAIL and ADMIN_PASSWORD, if no users exist
  └─ Phoenix server starts on :4000
```

## Standalone Docker

For users who already have PostgreSQL and S3-compatible storage and just need to run the control plane container.

### Prerequisites

- PostgreSQL 15+ (managed or self-hosted)
- S3-compatible storage (AWS S3, MinIO, DigitalOcean Spaces, etc.)
- Docker

### Pull or Build the Image

```bash
# Build from source
docker build -t zentinel-cp .
```

### Run Migrations and Create the First Admin

Before starting the application for the first time, run database migrations and create the first admin. Use the same secrets you will start the app with:

```bash
docker run --rm \
  -e DATABASE_URL="ecto://user:pass@db-host:5432/zentinel_cp" \
  -e SECRET_KEY_BASE="your-secret-key-base" \
  -e ENCRYPTION_KEY="your-encryption-key" \
  zentinel-cp bin/zentinel_cp eval "ZentinelCp.Release.migrate()"

docker run --rm \
  -e DATABASE_URL="ecto://user:pass@db-host:5432/zentinel_cp" \
  -e SECRET_KEY_BASE="your-secret-key-base" \
  -e ENCRYPTION_KEY="your-encryption-key" \
  -e ADMIN_EMAIL="you@example.com" \
  -e ADMIN_PASSWORD="a-long-unique-password" \
  zentinel-cp bin/zentinel_cp eval "ZentinelCp.Release.bootstrap_admin()"
```

### Start the Control Plane

```bash
docker run -d \
  --name zentinel-cp \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@db-host:5432/zentinel_cp" \
  -e SECRET_KEY_BASE="your-secret-key-base" \
  -e ENCRYPTION_KEY="your-encryption-key" \
  -e PHX_HOST="cp.example.com" \
  -e S3_ENDPOINT="https://s3.amazonaws.com" \
  -e S3_BUCKET="zentinel-bundles" \
  -e S3_ACCESS_KEY_ID="AKIA..." \
  -e S3_SECRET_ACCESS_KEY="..." \
  -e S3_REGION="us-east-1" \
  -e FORCE_SSL="true" \
  zentinel-cp
```

The entrypoint automatically runs migrations and creates the first admin on startup, so the separate migration step is only needed if you want to run migrations independently.

### Healthcheck

The container includes a built-in healthcheck:

```bash
curl -f http://localhost:4000/health
```

### Rollback Migrations

```bash
docker run --rm \
  -e DATABASE_URL="ecto://user:pass@db-host:5432/zentinel_cp" \
  -e SECRET_KEY_BASE="any-value" \
  -e ENCRYPTION_KEY="your-encryption-key" \
  zentinel-cp bin/zentinel_cp eval "ZentinelCp.Release.rollback(ZentinelCp.Repo, 20240101000000)"
```

Replace the version number with the migration timestamp you want to roll back to.

## From Source (Bare Metal / VM)

For users who want to build and run a native OTP release without Docker.

### Prerequisites

- Elixir 1.16+ and Erlang/OTP 26+
- PostgreSQL 15+
- S3-compatible storage
- `zentinel` CLI binary (for bundle validation/compilation)
- Node.js (for asset compilation)

### Build the Release

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane

export MIX_ENV=prod

mix deps.get --only prod
mix compile
mix assets.deploy
mix release
```

The release is built to `_build/prod/rel/zentinel_cp/`.

### Run Migrations and Create the First Admin

```bash
export DATABASE_URL="ecto://user:pass@localhost:5432/zentinel_cp"
export SECRET_KEY_BASE="your-secret-key-base"
export ENCRYPTION_KEY="your-encryption-key"
export ADMIN_EMAIL="you@example.com"
export ADMIN_PASSWORD="a-long-unique-password"

_build/prod/rel/zentinel_cp/bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
_build/prod/rel/zentinel_cp/bin/zentinel_cp eval "ZentinelCp.Release.bootstrap_admin()"
```

### Start the Server

```bash
export DATABASE_URL="ecto://user:pass@localhost:5432/zentinel_cp"
export SECRET_KEY_BASE="your-secret-key-base"
export ENCRYPTION_KEY="your-encryption-key"
export PHX_HOST="cp.example.com"
export S3_ENDPOINT="https://s3.amazonaws.com"
export S3_BUCKET="zentinel-bundles"
export S3_ACCESS_KEY_ID="AKIA..."
export S3_SECRET_ACCESS_KEY="..."
export ZENTINEL_BINARY="/usr/local/bin/zentinel"

PHX_SERVER=true _build/prod/rel/zentinel_cp/bin/zentinel_cp start
```

### systemd Service

Create `/etc/systemd/system/zentinel-cp.service`:

```ini
[Unit]
Description=Zentinel Control Plane
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=exec
User=zentinel
Group=zentinel
WorkingDirectory=/opt/zentinel-cp
ExecStart=/opt/zentinel-cp/bin/zentinel_cp start
ExecStop=/opt/zentinel-cp/bin/zentinel_cp stop
Restart=on-failure
RestartSec=5

Environment=PHX_SERVER=true
Environment=PORT=4000
Environment=PHX_HOST=cp.example.com
Environment=FORCE_SSL=true
Environment=POOL_SIZE=10
Environment=ZENTINEL_BINARY=/usr/local/bin/zentinel

EnvironmentFile=/etc/zentinel-cp/env

[Install]
WantedBy=multi-user.target
```

Store secrets in `/etc/zentinel-cp/env` (mode `0600`):

```bash
DATABASE_URL=ecto://zentinel:password@localhost:5432/zentinel_cp
SECRET_KEY_BASE=your-secret-key-base-here
ENCRYPTION_KEY=your-encryption-key-here
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=zentinel-bundles
S3_ACCESS_KEY_ID=AKIA...
S3_SECRET_ACCESS_KEY=...
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable zentinel-cp
sudo systemctl start zentinel-cp
sudo journalctl -u zentinel-cp -f
```

## Connecting Proxies

After deployment, see [PROXY-REGISTRATION.md](PROXY-REGISTRATION.md) for a complete guide on registering zentinel proxy instances with the control plane.

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
