# Getting Started

## Prerequisites

**Docker Compose (Option A):** Only [Docker](https://docs.docker.com/get-docker/) required — all dependencies included.

**Local development (Option B):**
- Elixir 1.16+ and Erlang/OTP 26+ (managed via [mise](https://mise.jdx.dev/))
- Docker — for MinIO (bundle storage)
- `zentinel` CLI binary — for configuration validation and compilation

## Docker Compose

Starts the control plane, PostgreSQL 17, and MinIO with one command:

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane
docker compose up
```

What happens:

1. Multi-stage Dockerfile builds the Elixir release (base: `hexpm/elixir:1.19.5-erlang-28.3.1-debian-bookworm`)
2. PostgreSQL 17 starts (port 5432, user: `zentinel`, password: `zentinel`)
3. MinIO starts (port 9000 API, port 9001 console)
4. `minio-init` container creates the `zentinel-bundles` bucket
5. App waits for PostgreSQL readiness (`pg_isready`), runs Ecto migrations
6. Database seeded with default org and admin user
7. Control plane available at **http://localhost:4000**

MinIO console: **http://localhost:9001** (credentials: `minioadmin` / `minioadmin`)

Tear down (including volumes):

```bash
docker compose down -v
```

### Services

| Service | Port | Purpose |
|---------|------|---------|
| `app` | 4000 | Control plane |
| `postgres` | 5432 | PostgreSQL 17 |
| `minio` | 9000, 9001 | S3-compatible storage |
| `minio-init` | — | Creates bundle bucket on startup |

### Environment Variables (Docker)

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABASE_URL` | `ecto://zentinel:zentinel@postgres:5432/zentinel_cp` | PostgreSQL connection |
| `SECRET_KEY_BASE` | Set in compose file | Phoenix secret key |
| `S3_ENDPOINT` | `http://minio:9000` | MinIO endpoint |
| `S3_BUCKET` | `zentinel-bundles` | Bundle storage bucket |
| `S3_ACCESS_KEY_ID` | `minioadmin` | MinIO access key |
| `S3_SECRET_ACCESS_KEY` | `minioadmin` | MinIO secret key |
| `S3_REGION` | `us-east-1` | S3 region |
| `PORT` | `4000` | HTTP listen port |

## Local Development

Hot-reloading with SQLite (no external databases):

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane

mise install          # Install Elixir/Erlang toolchain
mise run setup        # Fetch deps, create DB, migrate, seed
mise run dev          # Start Phoenix dev server with hot reload
```

Uses SQLite (zero configuration). MinIO starts via `docker-compose.dev.yml` for bundle storage.

Control plane starts at **http://localhost:4000**.

## Default Credentials

On first startup, the database is seeded with a default admin account:

| Field | Value |
|-------|-------|
| **Email** | `admin@localhost` |
| **Password** | `changeme123456` |
| **Role** | `admin` |

Created by `priv/repo/seeds.exs`. **Change these credentials immediately in any non-development environment.**

### Creating Your Own User

**Via the web UI:**

Navigate to `/register` and fill in the registration form.

**Via IEx console:**

```bash
mise run console
```

```elixir
ZentinelCp.Accounts.register_user(%{
  email: "you@example.com",
  password: "your-secure-password-here"
})
```

**Via Docker:**

```bash
docker compose exec app bin/zentinel_cp eval '
  ZentinelCp.Accounts.register_user(%{
    email: "you@example.com",
    password: "your-secure-password-here"
  })
'
```

Password requirements: minimum 12 characters, maximum 72 characters. Hashed with Argon2.

### User Roles

| Role | Permissions |
|------|-------------|
| `admin` | Full org control, manage members, projects, signing keys, API keys |
| `operator` | Manage projects, bundles, rollouts, services, nodes |
| `reader` | Read-only access to all resources |

Roles are per-organization. A user can have different roles in different orgs.

## First Steps After Login

1. **Create an Organization** — Organizations > New Organization. Enter a name; a URL-safe slug is auto-generated.

2. **Create a Project** — From the org dashboard, click New Project. Projects group related proxy configs, nodes, and bundles.

3. **Configure Services** — Services > New Service. Define route paths and upstreams (e.g., `/api/*` → `http://api.internal:8080`).

4. **Compile a Bundle** — Bundles > New Bundle. Enter KDL configuration or generate from services. Compilation runs in background.

5. **Register a Node** — Register a Zentinel proxy instance via the API:
   ```bash
   curl -X POST http://localhost:4000/api/v1/projects/my-project/nodes/register \
     -H "Content-Type: application/json" \
     -d '{"name": "proxy-1", "labels": {"env": "dev"}}'
   ```
   Store the returned `node_key` — it is only shown once.

6. **Deploy with a Rollout** — Rollouts > New Rollout. Select bundle, choose strategy (rolling, canary, blue-green, all-at-once), configure health gates, start.

## Next Steps

- [ARCHITECTURE.md](ARCHITECTURE.md) — System design and data flow
- [API.md](API.md) — Full REST API reference with curl examples
- [AUTHENTICATION.md](AUTHENTICATION.md) — API keys, node auth, SSO, MFA
- [CONFIGURATION.md](CONFIGURATION.md) — Services, upstreams, TLS, environment variables
- [DEPLOYMENT.md](DEPLOYMENT.md) — Production deployment and rollout strategies
- [SECURITY.md](SECURITY.md) — WAF, auth policies, bundle signing
- [OBSERVABILITY.md](OBSERVABILITY.md) — Prometheus, SLOs, alerts, tracing
- [DEVELOPMENT.md](DEVELOPMENT.md) — Building, testing, contributing
