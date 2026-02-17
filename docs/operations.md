# Operations

This guide covers user management, organization administration, audit logging, environment configuration, and background job operations.

## Users

### Registration

Users register with an email address and password:

- **Email**: Must contain `@`, max 160 characters, unique
- **Password**: 12-72 characters, hashed with Argon2

### Roles

Users have a global system role:

| Role | Permissions |
|------|-------------|
| `admin` | Full system access, manage users, view all audit logs |
| `operator` | Manage projects and resources within their orgs |
| `reader` | Read-only access within their orgs |

The global role is separate from per-org membership roles (see [Organizations](#organizations)).

### Profile Management

Users can update:
- **Email**: Requires current password verification
- **Password**: Requires current password, must meet minimum length

### Multi-Factor Authentication

Users can enable TOTP-based MFA (see [Security > TOTP](security.md#totp-multi-factor-authentication)):

1. Navigate to **Profile** settings
2. Enable TOTP — scan the QR code with an authenticator app
3. Enter a verification code to confirm
4. Save the 10 recovery codes securely

### SSO Login

When an SSO provider is configured for an org:
- Users can log in via OIDC or SAML
- New users are automatically provisioned (JIT) with a role based on IdP group mapping
- Password login may be disabled depending on provider settings

See [Security > SSO Integration](security.md#sso-integration) for setup.

## Organizations

Organizations are the multi-tenancy boundary. All projects and resources are owned by an org.

### Creating an Organization

Create an org with a name — a URL-safe slug is generated automatically:

- Name: "Acme Corp" → Slug: `acme-corp`
- Settings: JSON map for org-wide preferences

### Member Management

| Operation | Role Required | Description |
|-----------|---------------|-------------|
| Add member | `admin` | Invite a user with a role |
| Update role | `admin` | Change a member's role |
| Remove member | `admin` | Remove a user from the org |
| List members | Any member | View all org members |

### Membership Roles

| Role | Level | Permissions |
|------|-------|-------------|
| `admin` | 3 | Full org control, manage members, signing keys, SSO |
| `operator` | 2 | Create/manage projects, bundles, rollouts, services |
| `reader` | 1 | Read-only access to all resources |

Role checks are hierarchical: an `admin` satisfies any role requirement for `operator` or `reader`.

### Default Organization

On first setup, a "default" organization is created automatically. This provides backward compatibility for resources that existed before multi-org support.

## Audit Logging

Every mutation in the control plane is recorded in a tamper-evident audit log.

### What Gets Logged

| Resource | Actions |
|----------|---------|
| Bundles | created, compiled, promoted, revoked, assigned |
| Rollouts | created, started, paused, resumed, cancelled, completed, failed, approved, rejected |
| Nodes | registered, deleted, heartbeat, labels updated, pinned, unpinned |
| Services | created, updated, deleted, reordered |
| Certificates | created, updated, renewed, deleted |
| API Keys | created, revoked, deleted |
| Users | registered, email changed, role changed |
| Orgs | created, updated, member added/removed |
| Secrets | created, updated, rotated, deleted |
| WAF Policies | created, updated, deleted |

### Audit Log Fields

| Field | Description |
|-------|-------------|
| `actor_type` | Who performed the action: `user`, `api_key`, `node`, `system` |
| `actor_id` | ID of the actor |
| `action` | Action identifier (e.g., `bundle.created`, `rollout.paused`) |
| `resource_type` | Type of resource affected |
| `resource_id` | ID of the affected resource |
| `changes` | Map of what changed |
| `metadata` | Additional context |
| `project_id` | Project scope |
| `org_id` | Organization scope |

### Tamper-Evidence

Audit logs form a cryptographic chain:

1. Each entry has an `entry_hash` computed via HMAC-SHA256
2. Each entry includes the `previous_hash` from the prior entry
3. Periodic **checkpoints** digitally sign the chain state
4. The chain can be verified at any time via the API or UI

### Verifying the Audit Chain

```bash
curl http://localhost:4000/api/v1/audit/verify \
  -H "Authorization: Bearer API_KEY"
```

This verifies that no entries have been tampered with by recomputing hashes through the chain.

### Audit Checkpoints

Create signed checkpoints for point-in-time chain attestation:

```bash
curl -X POST http://localhost:4000/api/v1/audit/checkpoints \
  -H "Authorization: Bearer API_KEY"
```

Each checkpoint records:
- Sequence number
- Last entry ID and hash
- Digest of all entries since the previous checkpoint
- Digital signature
- Count of entries covered

### Querying Audit Logs

**Project-scoped**: View audit logs for a specific project, with filtering by actor, action, resource type, and date range.

**Global**: Admins can view audit logs across all projects.

**Resource history**: View the complete audit trail for a specific resource (e.g., all actions on a particular bundle).

**Real-time**: Subscribe to audit log events via PubSub for live updates in the UI.

## Environments

Environments define deployment stages within a project.

### Default Environments

Every new project gets three environments:

| Name | Slug | Ordinal | Color |
|------|------|---------|-------|
| Development | `dev` | 0 | Green (#22c55e) |
| Staging | `staging` | 1 | Yellow (#eab308) |
| Production | `production` | 2 | Red (#ef4444) |

### Custom Environments

You can create additional environments or modify the defaults:

| Property | Description |
|----------|-------------|
| `name` | Display name (1-50 characters) |
| `slug` | URL-safe identifier (auto-generated) |
| `description` | Purpose description |
| `color` | Hex color code for UI display |
| `ordinal` | Position in the promotion pipeline (lower = earlier) |
| `settings` | Per-environment overrides |

### Environment Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `approval_required` | Inherited from project | Require approvals for rollouts |
| `approvals_needed` | 1 | Number of approvals needed |
| `auto_rollback_enabled` | true | Auto-rollback on health gate failure |

### Using Environments

- **Node assignment**: Assign nodes to environments to separate dev, staging, and production fleets
- **Rollout scoping**: Target rollouts to a specific environment
- **Bundle promotion**: Promote bundles through the pipeline (dev → staging → production)
- **Freeze windows**: Create environment-specific deployment freezes
- **Secret scoping**: Store different secret values per environment

## Background Jobs

The control plane uses Oban for reliable background job processing. Jobs are stored in the database and survive application restarts.

### Job Queues

| Queue | Workers | Purpose |
|-------|---------|---------|
| `default` | CompileWorker, GCWorker | Bundle compilation, garbage collection |
| `rollouts` | RolloutTickWorker | Rollout state machine progression |
| `monitoring` | StalenessWorker, DriftWorker, SliWorker, AlertEvaluator | Health monitoring and alerting |
| `analytics` | RollupWorker, WafBaselineWorker, WafAnomalyWorker | Metric aggregation and analysis |
| `notifications` | DeliveryWorker | Notification delivery |

### Job Schedules

| Worker | Interval | Description |
|--------|----------|-------------|
| `RolloutTickWorker` | Every 5 seconds per rollout | Advances rollout batches, checks health gates |
| `StalenessWorker` | Periodic | Marks nodes offline after 120s without heartbeat |
| `DriftWorker` | Every 30 seconds | Detects configuration drift across the fleet |
| `SliWorker` | Every 5 minutes | Computes SLI values for all enabled SLOs |
| `AlertEvaluator` | Every 30 seconds | Evaluates alert rule conditions |
| `RollupWorker` | Every hour | Aggregates raw metrics into hourly/daily rollups |
| `WafBaselineWorker` | Every hour | Computes WAF statistical baselines |
| `WafAnomalyWorker` | Every 15 minutes | Detects WAF anomalies |
| `GCWorker` | Periodic | Cleans up old bundles from storage |

### Job Reliability

- Jobs have configurable `max_attempts` with automatic retry
- Failed jobs are logged with error details
- Unique constraints prevent duplicate jobs (e.g., one tick per rollout)
- The `RolloutTickWorker` self-reschedules after each tick to maintain the 5-second cadence

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Production | — | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Production | — | Phoenix secret for sessions and encryption |
| `PHX_HOST` | Production | `localhost` | Public hostname |
| `PORT` | No | `4000` | HTTP port |
| `POOL_SIZE` | No | `10` | Database connection pool size |
| `S3_BUCKET` | No | `zentinel-bundles` | S3 bucket for bundle storage |
| `S3_ENDPOINT` | No | `http://localhost:9000` | S3/MinIO endpoint |
| `S3_ACCESS_KEY_ID` | Production | — | S3 access key |
| `S3_SECRET_ACCESS_KEY` | Production | — | S3 secret key |
| `S3_REGION` | No | `us-east-1` | AWS region |
| `ZENTINEL_BINARY` | No | `zentinel` | Path to Zentinel CLI binary |
| `GITHUB_WEBHOOK_SECRET` | If using GitHub | — | HMAC secret for webhook verification |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | If using tracing | — | OpenTelemetry exporter endpoint |

### Database Configuration

| Environment | Adapter | Configuration |
|-------------|---------|---------------|
| Development | SQLite | Zero configuration, stored in `priv/` |
| Test | SQLite | Separate test database |
| Production | PostgreSQL | Via `DATABASE_URL` environment variable |

### Storage Backends

| Backend | Configuration | Use Case |
|---------|---------------|----------|
| S3 | `S3_*` environment variables | Production |
| Local filesystem | `backend: :local`, `local_dir: "priv/bundles"` | Development |

## Health Endpoints

| Endpoint | Auth | Description |
|----------|------|-------------|
| `GET /health` | None | Basic liveness check |
| `GET /ready` | None | Readiness check (database connectivity) |
| `GET /metrics` | None | Prometheus metrics endpoint |
