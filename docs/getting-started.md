# Getting Started

This guide walks you through installing Sentinel Control Plane, creating your first project, compiling a configuration bundle, registering a node, and deploying with a rollout.

## Prerequisites

- **Elixir** 1.16+ and **Erlang/OTP** 26+ (managed via [mise](https://mise.jdx.dev/))
- **PostgreSQL** 15+ (production) or SQLite (development — zero configuration)
- **S3-compatible storage** — MinIO for local development, AWS S3 for production
- **Sentinel CLI** — the `sentinel` binary for configuration validation and compilation

## Installation

```bash
# Clone the repository
git clone https://github.com/raskell-io/sentinel-control-plane.git
cd sentinel-control-plane

# Install tooling and dependencies
mise install
mise run setup

# Start the development server
mise run dev
```

The control plane starts at `http://localhost:4000`.

## Creating Your First User

Register an account through the web UI at `/register`, or create one via the console:

```bash
mise run console
```

```elixir
SentinelCp.Accounts.register_user(%{
  email: "admin@example.com",
  password: "your-secure-password"
})
```

## Creating an Organization

Organizations are the top-level tenant boundary. All projects, members, and signing keys belong to an org.

1. Log in to the web UI
2. Navigate to **Organizations** and click **New Organization**
3. Enter a name (e.g., "Acme Corp") — a URL-safe slug is generated automatically

See [Operations > Organizations](operations.md#organizations) for details on member management and roles.

## Creating a Project

Projects group related proxy configurations, nodes, bundles, and rollouts.

1. From your organization dashboard, click **New Project**
2. Enter a name and optional description
3. Optionally configure a GitHub repository for GitOps (see [Integrations > GitOps](integrations.md#gitops-webhooks))

The project is now ready for configuration.

## Configuring Services

Services define how Sentinel routes traffic. Each service maps an HTTP path to a backend upstream.

1. Navigate to your project and click **Services**
2. Click **New Service** and fill in:
   - **Name**: e.g., "API Backend"
   - **Route Path**: e.g., `/api/*`
   - **Upstream URL**: e.g., `http://api.internal:8080`
3. Optionally attach middlewares for rate limiting, caching, CORS, etc.

See [Configuration Management](configuration-management.md) for the full range of service options.

## Compiling a Bundle

Bundles are immutable, content-addressed configuration artifacts that Sentinel nodes consume.

### Via the Web UI

1. Navigate to **Bundles** and click **New Bundle**
2. Enter your KDL configuration or let it generate from your services
3. Click **Create** — compilation runs in the background
4. The bundle transitions from `compiling` to `compiled` when ready

### Via the API

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/bundles \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "config_source": "route \"/api/*\" {\n  upstream \"http://api.internal:8080\"\n}"
  }'
```

The response includes a `bundle_id`. Poll `GET /api/v1/projects/my-project/bundles/:id` until `status` is `"compiled"`.

During compilation, the control plane:
1. Validates the KDL configuration with `sentinel validate`
2. Assembles a `.tar.zst` archive with manifest, CA certs, and plugins
3. Uploads to S3/MinIO storage
4. Signs the bundle (if signing is enabled)
5. Scores risk against the previous bundle

See [Core Concepts > Bundles](core-concepts.md#bundles) for details.

## Registering a Node

Sentinel proxy nodes register with the control plane and then poll for bundle updates.

### Via the API

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/nodes/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "proxy-us-east-1",
    "labels": {"region": "us-east-1", "env": "production"}
  }'
```

The response includes a `node_id` and `node_key`. **Store the `node_key` securely** — it is only returned once and cannot be retrieved later.

Nodes authenticate with the control plane using either:
- **Static key**: `X-Sentinel-Node-Key` header (simple, suitable for getting started)
- **JWT token**: Exchange the static key for a short-lived JWT via `POST /api/v1/nodes/:id/token` (recommended for production)

See [Node Management](node-management.md) for the full node lifecycle.

## Deploying with a Rollout

Rollouts safely deploy a compiled bundle to your node fleet.

### Via the Web UI

1. Navigate to **Rollouts** and click **New Rollout**
2. Select the compiled bundle
3. Choose a deployment strategy:
   - **Rolling** (default): Deploy in batches with health checks between steps
   - **Canary**: Gradually increase traffic to the new bundle
   - **Blue-Green**: Deploy to standby slot, shift traffic, then swap
   - **All at Once**: Deploy to all nodes simultaneously
4. Configure health gates (heartbeat checks, error rate thresholds, latency limits)
5. Click **Create** and then **Start**

### Via the API

```bash
curl -X POST http://localhost:4000/api/v1/projects/my-project/rollouts \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "bundle_id": "BUNDLE_ID",
    "strategy": "rolling",
    "batch_size": 2,
    "target_selector": {"type": "all"},
    "health_gates": {"heartbeat_healthy": true}
  }'
```

The rollout engine advances through batches automatically, pausing if health gates fail. You can pause, resume, cancel, or rollback at any time.

See [Deployment & Rollouts](deployment-and-rollouts.md) for strategy details and advanced options.

## Next Steps

- [Core Concepts](core-concepts.md) — Understand the data model
- [Configuration Management](configuration-management.md) — Configure services, upstreams, TLS, and more
- [Security](security.md) — Set up WAF rules, auth policies, and bundle signing
- [Observability](observability.md) — Create SLOs, alerts, and dashboards
- [API Reference](api-reference.md) — Full API endpoint documentation
