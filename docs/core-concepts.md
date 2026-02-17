# Core Concepts

This document explains the fundamental resources and relationships in Zentinel Control Plane.

## Organizations

Organizations are the top-level tenant boundary. Every project, member, and signing key belongs to an org.

- **Slug**: Auto-generated URL-safe identifier (e.g., "acme-corp")
- **Settings**: JSON configuration for org-wide preferences
- **Members**: Users with per-org roles

### Membership Roles

| Role | Permissions |
|------|-------------|
| `admin` | Full org control, manage members, create/delete projects, manage signing keys |
| `operator` | Create and manage projects, bundles, rollouts, services, and nodes |
| `reader` | Read-only access to all resources |

Roles are hierarchical: admin > operator > reader. A user can have different roles in different organizations.

See [Operations > Organizations](operations.md#organizations) for management details.

## Projects

Projects group related proxy configurations within an organization. A project typically represents a single application, service domain, or deployment boundary.

Each project contains:
- **Nodes** — Zentinel proxy instances assigned to this project
- **Bundles** — Compiled configuration artifacts
- **Rollouts** — Deployment plans for distributing bundles
- **Services** — Proxy route definitions
- **Environments** — Deployment stages (dev, staging, production)
- **Notification channels and rules** — Event routing
- **SLOs and alert rules** — Monitoring configuration

### Project Settings

| Setting | Description |
|---------|-------------|
| `approval_required` | Require approvals before rollouts can start |
| `approvals_needed` | Number of approvals required (default: 1) |
| `drift_auto_remediation` | Automatically fix nodes that drift from expected configuration |
| `drift_check_interval` | How often to check for drift (default: 30 seconds) |
| `drift_alert_threshold` | Percentage of drifted nodes that triggers an alert |
| `portal_enabled` | Enable the developer portal for this project |
| `portal_access` | Portal access level: `"disabled"`, `"public"`, or `"authenticated"` |

### GitOps Integration

Projects can be linked to a Git repository for automatic bundle creation on push:

- **Repository**: Owner/repo format (e.g., `acme/proxy-config`)
- **Branch**: Target branch to watch (default: `main`)
- **Config Path**: Path to the KDL configuration file (default: `zentinel.kdl`)

See [Integrations > GitOps](integrations.md#gitops-webhooks) for setup.

## Environments

Environments represent deployment stages within a project. They form a promotion pipeline that bundles progress through.

Default environments (created automatically):

| Environment | Ordinal | Color | Purpose |
|-------------|---------|-------|---------|
| `dev` | 0 | Green | Development and testing |
| `staging` | 1 | Yellow | Pre-production validation |
| `production` | 2 | Red | Live traffic |

### Environment Settings

Each environment can override project-level settings:

- **Approval required** — Whether rollouts targeting this environment need approvals
- **Approvals needed** — Number of required approvals
- **Auto-rollback enabled** — Whether to automatically rollback on health gate failure

### Promotion Pipeline

Bundles are promoted through environments in ordinal order:

```
dev (ordinal 0)  →  staging (ordinal 1)  →  production (ordinal 2)
```

Each promotion creates a `BundlePromotion` record tracking who promoted it and when. A bundle can only be promoted to an environment once.

Nodes are assigned to environments, and rollouts can target a specific environment to deploy only to nodes in that stage.

## Bundles

Bundles are immutable, content-addressed configuration artifacts consumed by Zentinel proxy nodes.

### Bundle Lifecycle

```
created → compiling → compiled
                        ├──→ promoted (to environments)
                        └──→ revoked (prevents further distribution)
```

### Bundle Properties

| Property | Description |
|----------|-------------|
| `config_source` | Raw KDL configuration text |
| `config_hash` | SHA256 hash of the configuration source |
| `version` | Semantic version string |
| `checksum` | SHA256 hash of the compiled archive |
| `size` | Archive size in bytes |
| `manifest` | Contents listing (files, sizes) |
| `signature` | Ed25519 signature (if signing enabled) |
| `signing_key_id` | Identifier of the key used to sign |
| `sbom` | CycloneDX 1.5 Software Bill of Materials |
| `risk_level` | Automatic risk assessment: `low`, `medium`, `high` |
| `risk_reasons` | What triggered the risk level (auth changes, TLS changes, etc.) |
| `parent_id` | Previous bundle for diff/lineage tracking |

### Risk Scoring

When a bundle is compiled, it is automatically scored against the previous bundle:

- **High risk**: Auth policy or TLS configuration changed
- **Medium risk**: Upstream removed, rate limits changed, or >10 route changes
- **Low risk**: No significant changes detected

### SBOM Generation

Each compiled bundle includes a CycloneDX 1.5 SBOM listing all components extracted from the KDL configuration: listeners, routes, upstreams, and agents. This supports supply chain visibility and compliance requirements.

### Bundle Diff

You can compare any two bundles to see:

- **Config diff**: Line-level changes with side-by-side display
- **Manifest diff**: Added, removed, and modified files
- **Semantic diff**: Services added/removed/modified, settings changes

See [Configuration Management](configuration-management.md) for how to define the configuration that goes into bundles.

## Nodes

Nodes are Zentinel proxy instances that pull configuration bundles from the control plane.

### Node Properties

| Property | Description |
|----------|-------------|
| `name` | Unique name within the project |
| `status` | `online`, `offline`, or `unknown` |
| `labels` | Key-value metadata for targeting (e.g., `region: us-east-1`) |
| `capabilities` | Feature flags and version info |
| `version` | Zentinel software version |
| `ip`, `hostname` | Network information (updated via heartbeats) |
| `active_bundle_id` | Currently running bundle |
| `staged_bundle_id` | Bundle waiting to be activated |
| `expected_bundle_id` | Bundle the control plane expects the node to run |
| `auth_method` | `static_key` or `jwt` |

### Node Lifecycle

```
Register → Online (heartbeating) → Offline (stale) → Decommission (delete)
```

- **Registration**: Node calls the registration API and receives a one-time `node_key`
- **Heartbeating**: Node sends periodic heartbeats with health metrics and bundle status
- **Staleness**: Nodes not seen for 120 seconds are automatically marked offline
- **Drift**: Detected when `active_bundle_id` differs from `expected_bundle_id`

See [Node Management](node-management.md) for the full lifecycle.

## Rollouts

Rollouts orchestrate the safe deployment of bundles to nodes.

### Rollout States

```
pending → running → completed
           │  ↑
           ▼  │
         paused
           │
           ▼
       cancelled / failed
```

### Deployment Strategies

| Strategy | Description |
|----------|-------------|
| `rolling` | Deploy in fixed-size batches with health checks between each |
| `canary` | Progressive traffic increase (e.g., 5% → 25% → 50% → 100%) with statistical analysis |
| `blue_green` | Deploy to standby slot, gradually shift traffic, validate, then swap |
| `all_at_once` | Deploy to all target nodes simultaneously |

### Target Selection

Rollouts target nodes using selectors:

- `{"type": "all"}` — All nodes in the project
- `{"type": "labels", "labels": {"env": "prod"}}` — Nodes matching labels
- `{"type": "node_ids", "node_ids": ["..."]}` — Specific nodes by ID
- `{"type": "groups", "group_ids": ["..."]}` — Nodes in specific groups

### Health Gates

Between batches, the rollout engine verifies:

| Gate | Description |
|------|-------------|
| `heartbeat_healthy` | All nodes in the batch are reporting heartbeats |
| `max_error_rate` | Error rate stays below threshold (percentage) |
| `max_latency_ms` | P99 latency stays below threshold (milliseconds) |
| `max_cpu_percent` | CPU usage stays below threshold |
| `max_memory_percent` | Memory usage stays below threshold |

Custom health check endpoints can also be configured per project.

### Approvals

Rollouts can require approval before starting. The approval workflow supports:

- Configurable number of required approvals per environment
- Approvers cannot approve their own rollouts
- Rejection requires a comment
- Automatic transition when approval threshold is met

### Freeze Windows

Deployment freeze windows prevent rollout creation during specified time periods (e.g., during holidays or critical business events). Freeze windows can be project-wide or scoped to a specific environment.

See [Deployment & Rollouts](deployment-and-rollouts.md) for strategy details and operational controls.

## Config Validation Rules

Projects can define custom validation rules applied during bundle compilation:

| Rule Type | Description |
|-----------|-------------|
| `required_field` | A specific field must be present in the configuration |
| `forbidden_pattern` | A regex pattern that must not appear |
| `allowed_pattern` | A regex pattern that must match |
| `max_size` | Maximum configuration file size in bytes |
| `json_schema` | Configuration must validate against a JSON schema |

Rules have configurable severity (`error`, `warning`, `info`) and can be enabled or disabled.

See [Advanced Topics > Validation Rules](advanced-topics.md#config-validation-rules) for examples.
