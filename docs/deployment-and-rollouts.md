# Deployment & Rollouts

This guide covers how to safely deploy configuration bundles to your Sentinel proxy fleet using rollouts.

## Overview

Rollouts orchestrate the deployment of a compiled [bundle](core-concepts.md#bundles) to a set of [nodes](core-concepts.md#nodes). The rollout engine:

- Divides target nodes into batches
- Deploys one batch at a time
- Verifies health gates between batches
- Automatically pauses or rolls back on failure
- Ticks every 5 seconds to advance state

## Creating a Rollout

### Required Fields

| Field | Description |
|-------|-------------|
| `bundle_id` | The compiled bundle to deploy |
| `target_selector` | Which nodes to deploy to (see below) |

### Optional Fields

| Field | Default | Description |
|-------|---------|-------------|
| `strategy` | `rolling` | Deployment strategy |
| `batch_size` | `1` | Nodes per batch |
| `batch_percentage` | — | Percentage of total per batch (alternative to batch_size) |
| `max_unavailable` | `0` | Maximum offline nodes tolerated per step |
| `health_gates` | `{"heartbeat_healthy": true}` | Verification criteria |
| `progress_deadline_seconds` | `600` | Max seconds per step before failure |
| `auto_rollback` | `false` | Auto-rollback on sustained health gate failure |
| `rollback_threshold` | `50` | Success percentage for rollback decision |
| `environment_id` | — | Scope to a specific environment |
| `scheduled_at` | — | Future timestamp for scheduled deployment |

### Target Selectors

```json
// All nodes in the project
{"type": "all"}

// Nodes matching labels
{"type": "labels", "labels": {"region": "us-east-1", "env": "production"}}

// Specific nodes
{"type": "node_ids", "node_ids": ["node-uuid-1", "node-uuid-2"]}

// Nodes in groups
{"type": "groups", "group_ids": ["group-uuid-1"]}
```

Pinned nodes (nodes locked to a specific bundle) are automatically excluded unless the rollout deploys their pinned bundle.

## Deployment Strategies

### Rolling

The default strategy. Deploys in fixed-size batches with health verification between each.

```
Batch 1: [Node A, Node B]  →  verify health  →
Batch 2: [Node C, Node D]  →  verify health  →
Batch 3: [Node E]          →  verify health  →  complete
```

**When to use**: Most deployments. Provides a good balance of safety and speed.

**Configuration**:
- `batch_size`: Number of nodes per batch
- `batch_percentage`: Alternative — percentage of fleet per batch

### Canary

Progressive traffic increase with statistical analysis comparing canary nodes against the baseline.

```
Step 1: 5% of nodes   →  analyze metrics  →  promote/rollback
Step 2: 25% of nodes  →  analyze metrics  →  promote/rollback
Step 3: 50% of nodes  →  analyze metrics  →  promote/rollback
Step 4: 100% of nodes →  complete
```

**When to use**: High-risk changes where you want data-driven promotion decisions.

**Configuration**:
```json
{
  "strategy": "canary",
  "canary_analysis_config": {
    "error_rate_threshold": 5.0,
    "latency_p99_threshold_ms": 500,
    "analysis_window_minutes": 5,
    "confidence_level": 0.95,
    "steps": [5, 25, 50, 100]
  }
}
```

**Analysis decisions**:
- **Promote**: Canary metrics are within thresholds — advance to next step
- **Rollback**: Canary error rate or latency exceeds thresholds or is significantly worse than baseline
- **Extend**: Insufficient data (< 10 requests) — wait for more traffic

### Blue-Green

Deploy to a standby slot, gradually shift traffic, validate, then swap.

```
Step 0: Deploy to green nodes (0% traffic)  →  verify health
Step 1: Shift 10% traffic to green          →  validate
Step 2: Shift 50% traffic to green          →  validate
Step 3: Shift 100% traffic to green         →  validate
Step 4: Deploy to blue nodes (catch-up)     →  complete
```

**When to use**: Zero-downtime deployments with instant rollback capability.

**Configuration**:
```json
{
  "strategy": "blue_green",
  "blue_green_config": {
    "traffic_steps": [10, 50, 100],
    "auto_advance": false,
    "advance_delay_seconds": 60
  },
  "validation_period_seconds": 300
}
```

**Controls**:
- If `auto_advance` is `false`, the rollout pauses after each validation period — an operator must manually advance
- `swap_slot` — Swap the active deployment slot (blue ↔ green)
- `instant_rollback` — Immediately set traffic to 0% on green, cancel rollout

### All at Once

Deploy to all target nodes simultaneously. No batching.

**When to use**: Non-critical environments, development, or when speed matters more than safety.

## Health Gates

Health gates are verification criteria checked between rollout batches. If any gate fails, the rollout pauses (or auto-rolls back if configured).

### Built-in Gates

| Gate | Type | Description |
|------|------|-------------|
| `heartbeat_healthy` | Boolean | All nodes in the batch must be sending heartbeats |
| `max_error_rate` | Number | Error rate must stay below this percentage |
| `max_latency_ms` | Number | P99 latency must stay below this value in milliseconds |
| `max_cpu_percent` | Number | CPU usage must stay below this percentage |
| `max_memory_percent` | Number | Memory usage must stay below this percentage |

Example:
```json
{
  "heartbeat_healthy": true,
  "max_error_rate": 5.0,
  "max_latency_ms": 200,
  "max_cpu_percent": 80
}
```

### Custom Health Check Endpoints

Define HTTP endpoints that the rollout engine calls to verify health:

| Property | Default | Description |
|----------|---------|-------------|
| `url` | — | HTTP(S) URL to check |
| `method` | `GET` | HTTP method: GET, POST, or HEAD |
| `timeout_ms` | `5000` | Request timeout (max 60 seconds) |
| `expected_status` | `200` | Expected HTTP status code |
| `expected_body_contains` | — | Response body must contain this string |
| `headers` | `{}` | Custom request headers |

Custom health checks can be tested independently before using them in a rollout.

### Progress Deadline

Each rollout step has a progress deadline (default: 600 seconds). If nodes haven't activated the bundle within this deadline, the step is marked as failed. If `auto_rollback` is enabled, the rollout automatically rolls back.

## Approval Workflow

Rollouts can require approval before starting. This is configured at the project or environment level.

### Flow

```
Create rollout (pending)
       │
       ▼
Submit for approval (pending_approval)
       │
       ├── Approve (by N users) → approved → can start
       │
       └── Reject (with comment) → rejected → cannot start
```

### Rules

- **Self-approval is not allowed** — The rollout creator cannot approve their own rollout
- **Threshold**: The number of required approvals is configurable per environment
- **Roles**: Only users with sufficient org membership roles can approve
- **Visibility**: All pending approvals are listed across the organization

### Viewing Approvals

The **Approvals** page shows all rollouts pending approval across your organization. Each entry shows the rollout details, who requested it, and the current approval count.

## Freeze Windows

Freeze windows prevent rollout creation during specified time periods.

### Creating a Freeze Window

| Property | Description |
|----------|-------------|
| `name` | Descriptive name (e.g., "Holiday Freeze") |
| `starts_at` | When the freeze begins |
| `ends_at` | When the freeze ends (must be after starts_at) |
| `reason` | Why deployments are frozen |
| `environment_id` | Optional — scope to a specific environment (nil = project-wide) |

When a freeze window is active, creating a rollout returns an error with the freeze window details. This can be overridden with `override_freeze: true` for emergency deployments.

## Rollout Templates

Save common rollout configurations as templates to avoid re-entering settings each time.

### Template Properties

Templates capture all rollout settings: strategy, batch size, health gates, auto-rollback configuration, canary/blue-green settings, and more. One template per project can be marked as the **default**, which pre-fills the rollout creation form.

## Operational Controls

### Pause and Resume

Pause a running rollout to halt progression. The current batch continues but no new batches start. Resume to continue from where you left off.

```
POST /api/v1/projects/:slug/rollouts/:id/pause
POST /api/v1/projects/:slug/rollouts/:id/resume
```

### Cancel

Cancel a running or paused rollout. Nodes that haven't activated the new bundle remain on their current configuration.

```
POST /api/v1/projects/:slug/rollouts/:id/cancel
```

### Rollback

Cancel the rollout and revert the `staged_bundle_id` on all affected nodes to their previous bundle.

```
POST /api/v1/projects/:slug/rollouts/:id/rollback
```

### Blue-Green Controls

| Action | Description |
|--------|-------------|
| Advance Traffic | Resume traffic shifting from a validation pause |
| Swap Slot | Swap the active deployment slot (blue ↔ green) |
| Instant Rollback | Set traffic to 0% on green, cancel rollout, clear staged bundles |

### Progress Monitoring

Track rollout progress in the UI or via the API:

```
GET /api/v1/projects/:slug/rollouts/:id
```

The response includes:
- Overall state and progress (total, pending, active, failed nodes)
- Per-step state and timing
- Per-node bundle status (pending → staging → staged → activating → active)

## Drift Detection

After a rollout completes, the control plane continuously monitors for **configuration drift** — when a node's active bundle doesn't match its expected bundle.

### How Drift Works

1. The `DriftWorker` runs every 30 seconds (configurable per project)
2. Compares `active_bundle_id` vs `expected_bundle_id` for all online nodes
3. Creates a drift event with severity based on the number of configuration changes
4. Emits a `drift.detected` event for notification routing

### Severity Levels

| Severity | Criteria |
|----------|----------|
| `critical` | >50 changes or node has no active bundle |
| `high` | >20 changes |
| `medium` | >5 changes |
| `low` | ≤5 changes |

### Auto-Remediation

If `drift_auto_remediation` is enabled on the project, the control plane automatically creates a rollout targeting just the drifted node to restore the expected bundle.

### Alert Thresholds

Configure `drift_alert_threshold` (percentage) and `drift_alert_node_count` (absolute count) to trigger alerts when too many nodes are drifted. These emit `drift.threshold_exceeded` events.

See [Node Management > Drift Detection](node-management.md#drift-detection) for more details.

## Scheduled Rollouts

Rollouts can be scheduled for future execution by setting `scheduled_at`. Scheduled rollouts appear in the **Schedule** view and are automatically started at the scheduled time.

## Environment-Scoped Rollouts

When an `environment_id` is specified, the rollout only targets nodes assigned to that environment. This enables staged deployments through the promotion pipeline:

1. Deploy to `dev` environment
2. Validate, then deploy to `staging`
3. Validate, then deploy to `production`

See [Core Concepts > Environments](core-concepts.md#environments) for the promotion pipeline.
