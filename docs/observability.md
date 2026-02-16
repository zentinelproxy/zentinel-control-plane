# Observability

This guide covers monitoring, alerting, analytics, and instrumentation in Sentinel Control Plane.

## Dashboard

The control plane provides real-time dashboards at two levels.

### Organization Dashboard

The org dashboard (`/orgs/:org_slug/dashboard`) shows a fleet-wide overview:

- **Node Health**: Total, online, offline, and unknown counts across all projects
- **Drift Health**: Managed nodes, drifted count, in-sync count, active/resolved drift events
- **Circuit Breakers**: Upstream group states (closed, open, half-open) across the fleet
- **Active Rollouts**: Count of currently running rollouts
- **Recent Bundles**: Bundles compiled in the last 7 days
- **Deployment Success Rate**: Percentage of successful rollouts
- **WAF Anomalies**: Active anomaly count
- **Recent Activity**: Live audit log feed

### Project Dashboard

The project dashboard shows project-specific status:

- **Node Stats**: Counts by status for nodes in the project
- **Active Rollouts**: Currently running rollouts
- **Latest Bundles**: 5 most recent bundles with status
- **Latest Rollouts**: 5 most recent rollouts with state
- **SLO Summary**: Total, healthy, warning, and breached SLO counts
- **Firing Alerts**: Count of active alerts

Both dashboards update in real-time via LiveView and PubSub subscriptions.

## Service Level Objectives

SLOs define reliability targets for your services. Each SLO tracks a Service Level Indicator (SLI) against a target over a rolling time window.

### Creating an SLO

| Property | Description |
|----------|-------------|
| `name` | Descriptive name (unique per project) |
| `description` | What this SLO measures |
| `sli_type` | Indicator type (see below) |
| `target` | Target threshold value |
| `window_days` | Rolling window (default: 30 days) |
| `service_id` | Optional — scope to a specific service |

### SLI Types

| Type | Measurement | Target Meaning |
|------|-------------|----------------|
| `availability` | `(1 - errors_5xx / total_requests) * 100` | Percentage (e.g., 99.9) |
| `error_rate` | `error_count / total_requests * 100` | Max percentage (e.g., 1.0) |
| `latency_p99` | Average P99 latency across the window | Max milliseconds (e.g., 500) |
| `latency_p95` | Average P95 latency across the window | Max milliseconds (e.g., 200) |

### Error Budget

Each SLO has an error budget that represents how much room remains before breaching the target:

- **Budget remaining ≥ 50%**: Status is `healthy`
- **0% < Budget < 50%**: Status is `warning`
- **Budget ≤ 0%**: Status is `breached`

Error budgets are computed by the `SliWorker` every 5 minutes using metrics from the `service_metrics` table.

### Burn Rate

The burn rate indicates how quickly the error budget is being consumed. A burn rate of 1.0 means the budget will be exhausted exactly at the end of the window. Higher values indicate faster consumption.

Burn rate is a common input for alert rules (see [Alert Rules](#alert-rules)).

## Alert Rules

Alert rules define conditions that trigger notifications when met.

### Creating an Alert Rule

| Property | Description |
|----------|-------------|
| `name` | Display name (unique per project) |
| `rule_type` | `metric`, `slo`, or `threshold` |
| `condition` | Condition specification (see below) |
| `severity` | `critical`, `warning`, or `info` |
| `for_seconds` | Grace period before firing (default: 0) |
| `channel_ids` | Notification channels to alert |
| `labels` | Metadata labels for grouping |

### Rule Types

**Metric rules** — Alert based on service metrics:

```json
{
  "metric": "error_rate",
  "operator": ">",
  "value": 5.0,
  "service_id": "optional-service-uuid",
  "window_minutes": 5
}
```

Supported metrics: `error_rate`, `latency_p99`, `latency_p95`, `error_count`, `request_count`, `5xx_count`

Supported operators: `>`, `<`, `>=`, `<=`, `==`, `!=`

**SLO rules** — Alert based on SLO burn rate:

```json
{
  "slo_id": "slo-uuid",
  "burn_rate_threshold": 10.0
}
```

**Threshold rules** — Same as metric rules (alias for generic threshold conditions).

### Alert States

Alerts follow a state machine:

```
inactive → pending (if for_seconds > 0) → firing → resolved
inactive → firing (if for_seconds == 0)
pending → resolved (condition clears during grace period)
```

Each state transition is recorded with the metric value at that time.

### Alert Evaluation

The `AlertEvaluator` worker runs every 30 seconds:

1. Evaluates all enabled, non-silenced alert rules
2. Queries service metrics for the configured time window
3. Compares values against conditions
4. Manages state transitions (inactive → pending → firing → resolved)
5. Sends notifications on state changes
6. Publishes updates via PubSub for real-time UI updates

### Silencing Alerts

Silence an alert rule until a specified datetime to suppress notifications during maintenance:

```
POST: silence_alert_rule(rule, silenced_until)
```

The rule continues to be evaluated but notifications are suppressed and new alert states are not created.

### Acknowledging Alerts

Firing alerts can be acknowledged by a user to indicate they are being investigated. This doesn't resolve the alert but records who acknowledged it and when.

### Viewing Alerts

The **Alerts** page shows:

- **Firing alerts**: Active alerts with severity, value, and duration
- **Pending alerts**: Alerts in the grace period before firing
- **Alert rules**: All configured rules with enable/disable controls
- **Alert history**: Paginated history of all state transitions

## Service Analytics

### Service Metrics

Nodes push request metrics to the control plane periodically. Metrics are stored per service per time period:

| Metric | Description |
|--------|-------------|
| `request_count` | Total requests |
| `error_count` | Total errors |
| `latency_p50_ms` | Median latency |
| `latency_p95_ms` | 95th percentile latency |
| `latency_p99_ms` | 99th percentile latency |
| `bandwidth_in_bytes` | Inbound bandwidth |
| `bandwidth_out_bytes` | Outbound bandwidth |
| `status_2xx` through `status_5xx` | Response status code counts |
| `top_paths` | Most requested paths |
| `top_consumers` | Top API consumers |

### Request Logs

Individual request records with:

- Timestamp, method, path, status code
- Latency, request/response size
- Client IP, user agent
- Service and node association

### Metric Rollups

Raw metrics are automatically aggregated:

| Period | Schedule | Retention |
|--------|----------|-----------|
| Raw | Every metric push | 7 days (configurable) |
| Hourly | Every hour | Indefinite |
| Daily | At midnight UTC | Indefinite |

The `RollupWorker` handles aggregation and pruning.

### Analytics Dashboard

The analytics page shows time-series charts for:

- Request volume and error rates per service
- Latency percentiles over time
- Status code distribution
- Bandwidth usage

## WAF Analytics

WAF events from across the fleet are aggregated for security analysis.

### WAF Event Properties

Each WAF event records:

| Property | Description |
|----------|-------------|
| `rule_type` | Category: sqli, xss, rfi, lfi, rce, scanner, custom |
| `rule_id` | Specific rule identifier |
| `action` | What happened: blocked, logged, challenged |
| `severity` | Rule severity: critical, high, medium, low |
| `client_ip` | Attacker's IP address |
| `method`, `path` | Targeted HTTP method and path |
| `matched_data` | What triggered the rule match |
| `geo_country` | Geographic location (if available) |

### WAF Baselines

The `WafBaselineWorker` runs hourly to compute statistical baselines over a 14-day rolling window:

| Baseline Metric | Description |
|-----------------|-------------|
| `total_blocks` | Mean and standard deviation of hourly block counts |
| `unique_ips` | Distribution of unique attacker IPs |
| `block_rate` | Rate of blocks per request |
| `blocks_by_rule` | Per-rule block counts |

### Anomaly Detection

The `WafAnomalyWorker` runs every 15 minutes and applies detection methods:

| Method | Detection |
|--------|-----------|
| **Spike Detection** | Z-score analysis — flags when current value is >2.5 standard deviations from baseline |
| **New Vector Detection** | Identifies rule types not seen in the baseline period |
| **IP Burst Detection** | Detects unusual changes in IP distribution |
| **Rate Change Detection** | Detects unexpected changes in block rate |

Anomalies are created with severity, description, observed vs. expected values, and deviation sigma (z-score). They follow a lifecycle:

```
active → acknowledged → resolved
active → false_positive
```

Anomalies emit `security.waf_anomaly` events for notification routing.

## Prometheus Metrics

The control plane exposes Prometheus metrics at `/metrics` via PromEx.

### Custom Sentinel Metrics

**Gauge metrics** (polled every 15 seconds):

| Metric | Labels | Description |
|--------|--------|-------------|
| `sentinel_cp_nodes_total` | `status` | Node count by status |
| `sentinel_cp_rollouts_active` | — | Active rollout count |
| `sentinel_cp_drift_events_active` | — | Unresolved drift events |
| `sentinel_cp_drift_nodes_drifted` | — | Currently drifted nodes |
| `sentinel_cp_slos_total` | `status` | SLO count by status (healthy/warning/breached) |
| `sentinel_cp_alerts_firing` | — | Currently firing alerts |

**Counter metrics** (event-driven):

| Metric | Labels | Description |
|--------|--------|-------------|
| `sentinel_cp_bundles_total` | `status` | Bundles by compilation status |
| `sentinel_cp_webhook_events_total` | `event_type` | Webhook events received |
| `sentinel_cp_drift_events_total` | `type` | Drift events (detected/resolved) |

### Standard Metrics

PromEx also exposes standard BEAM, Phoenix, Ecto, and Oban metrics:

- **BEAM**: VM memory, process count, schedulers, garbage collection
- **Phoenix**: HTTP request latency, status codes, LiveView render times
- **Ecto**: Query execution time, queue wait time, transaction count
- **Oban**: Job execution time, queue depth, success/failure rates

## OpenTelemetry

The control plane emits OpenTelemetry traces for key operations when `OTEL_EXPORTER_OTLP_ENDPOINT` is configured.

### Traced Operations

| Span Name | Attributes | Description |
|-----------|------------|-------------|
| `sentinel_cp.bundle_compilation` | `bundle_id` | Full compilation pipeline |
| `sentinel_cp.rollout_tick` | `rollout_id` | Each rollout tick cycle |
| `sentinel_cp.webhook_processing` | `provider` | Webhook event processing |
| `sentinel_cp.node_heartbeat` | `node_id` | Heartbeat recording |

Each span captures timing, errors, and relevant metadata as span attributes.
