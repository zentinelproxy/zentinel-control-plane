# Observability

## Prometheus Metrics

Exposed at `GET /metrics` (no auth). Powered by PromEx.

### Metric Categories

| Category | Examples |
|----------|---------|
| BEAM VM | Memory, process count, scheduler utilization, GC |
| Phoenix | Request count, duration, status codes |
| Ecto | Query count, duration, queue time |
| Oban | Job count, duration, state transitions |
| Zentinel (custom) | Node counts, drift events, SLO status, active rollouts, bundle sizes |

### Scrape Config

```yaml
scrape_configs:
  - job_name: zentinel-control-plane
    static_configs:
      - targets: ['localhost:4000']
    metrics_path: /metrics
    scrape_interval: 15s
```

## SLOs / SLIs

Define availability, latency, and error rate targets with error budget tracking.

- **Target types**: availability (%), latency (P99 ms), error rate (%)
- **Windows**: rolling (e.g., 30 days) or calendar-based
- **Error budgets**: computed from target vs actual
- **SliWorker**: computes SLI values every 5 minutes

Configure via the web UI (SLOs page) or API.

## Alert Rules

Metric-based and SLO burn-rate alerts.

- **Metric-based**: threshold on any collected metric
- **SLO burn-rate**: fire when error budget consumed faster than expected
- **Severity**: `critical`, `warning`, `info`
- **Grace period**: delay before firing to avoid flapping
- **AlertEvaluator**: runs every 30 seconds

Alerts route to notification channels.

## Service Analytics

Per-service metrics collected from nodes:

| Metric | Description |
|--------|-------------|
| Request count | Total requests per period |
| Error count | 4xx and 5xx responses |
| Latency percentiles | P50, P95, P99 |
| Bandwidth | Bytes in/out |
| Status code distribution | 2xx, 3xx, 4xx, 5xx |

### Metric Rollups

`RollupWorker` aggregates raw metrics into hourly and daily summaries. Configurable retention.

## WAF Analytics

Security event processing from across the fleet.

- **Event tracking**: every blocked/logged/challenged request — rule ID, client IP, path, matched data
- **Baselines**: hourly computation over 14-day rolling windows (total blocks, unique IPs, block rates)
- **Anomaly detection**: Z-score analysis (threshold >2.5σ)
  - Spike detection: sudden increase in block count
  - New attack vectors: unseen rule IDs
  - IP bursts: single IP exceeding baseline
  - Rate changes: significant shift in block rate

Workers: `WafBaselineWorker` (hourly), `WafAnomalyWorker` (every 15 min).

## OpenTelemetry

Distributed tracing via OpenTelemetry.

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4318
```

Batch span processor wraps:
- Bundle compilation
- Rollout ticks
- Webhook processing
- Node heartbeats

Config in `config/runtime.exs`:
```elixir
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: {:opentelemetry_exporter, %{}}
```

## Node Monitoring

### Heartbeats

Nodes send periodic heartbeats (every 10-30s) with:
- Health metrics (CPU, memory)
- Active and staged bundle IDs
- Software version
- Network info (IP, hostname)

### Staleness Detection

`StalenessWorker` marks nodes `offline` after 120 seconds without a heartbeat.

### Drift Detection

`DriftWorker` runs every 30 seconds. Drift detected when `active_bundle_id != expected_bundle_id`.

| Setting | Description |
|---------|-------------|
| `drift_auto_remediation` | Automatically reassign expected bundle |
| `drift_check_interval` | Check frequency (default: 30s) |
| `drift_alert_threshold` | % of drifted nodes that triggers alert |

Drift events viewable in the UI, exportable as CSV.

### Node Groups

Label-based grouping for targeting. Nodes can belong to multiple groups. Groups used in rollout target selectors.

## Notification Channels

Route operational events to external systems.

| Channel | Description |
|---------|-------------|
| Slack | Webhook-based messages |
| PagerDuty | Incident creation |
| Microsoft Teams | Webhook messages |
| Email | Via Swoosh mailer |
| Generic Webhook | Custom HTTP POST |

### Event Routing

Pattern-based notification rules:

| Pattern | Events |
|---------|--------|
| `rollout.*` | Rollout state changes |
| `bundle.*` | Bundle promotions, compilations |
| `drift.*` | Configuration drift detected/resolved |
| `security.*` | Security-related events |
| `waf.*` | WAF anomalies |
| `alert.*` | Alert state transitions |

Delivery: exponential backoff retries with dead-letter queue.

## Audit Logging

Immutable audit log with HMAC chain verification.

- All mutations logged with actor, resource, action, timestamp
- Org and project context captured
- HMAC chain: each entry's hash includes previous entry's hash
- Checkpoints: periodic chain verification snapshots

### Verification

```bash
curl http://localhost:4000/api/v1/audit/verify \
  -H "Authorization: Bearer $API_KEY"
```

### Export

Audit logs viewable in the web UI. Exportable via API.

## Health Endpoints

```
GET /health    # Liveness — returns 200 if app is running
GET /ready     # Readiness — returns 200 if DB and services ready
GET /metrics   # Prometheus metrics
```

No authentication required. Suitable for load balancer health checks and monitoring.
