# Advanced Topics

This guide covers the node fleet simulator, service topology visualization, config validation rules, and troubleshooting.

## Node Fleet Simulator

The control plane includes a built-in simulator for spawning virtual Zentinel nodes. This is useful for testing rollouts, drift detection, and dashboards without deploying real proxy instances.

### Spawning Simulated Nodes

From an IEx console:

```elixir
alias ZentinelCp.Simulator.Fleet

# Spawn 10 simulated nodes for a project
{:ok, nodes} = Fleet.spawn_nodes("my-project", 10,
  base_url: "http://localhost:4000",
  name_prefix: "sim-node",
  poll_interval_ms: 5000,
  heartbeat_interval_ms: 10000,
  apply_delay_ms: 1000,
  failure_rate: 0.0
)
```

### Simulator Options

| Option | Default | Description |
|--------|---------|-------------|
| `base_url` | `http://localhost:4000` | Control plane URL |
| `name_prefix` | `sim-node` | Prefix for node names (e.g., `sim-node-001`) |
| `poll_interval_ms` | `5000` | How often nodes poll for bundle updates |
| `heartbeat_interval_ms` | `10000` | How often nodes send heartbeats |
| `apply_delay_ms` | `1000` | Simulated delay for applying a bundle |
| `failure_rate` | `0.0` | Probability (0.0-1.0) that bundle apply fails |

### Simulated Node Lifecycle

Each simulated node runs as a GenServer and follows this lifecycle:

1. **Register** — Calls the registration API, receives `node_id` and `node_key`
2. **Heartbeat** — Sends periodic heartbeats with simulated health metrics (CPU, memory, uptime)
3. **Poll** — Checks for new bundles via the polling API
4. **Apply** — When a new bundle is detected, simulates applying it (with optional delay and failure)

### Managing the Fleet

```elixir
# Check fleet status
Fleet.get_summary(nodes)
# => %{total: 10, connected: 10, disconnected: 0, initializing: 0, stopped: 0}

# Get detailed state of all nodes
Fleet.get_all_states(nodes)

# Trigger random failures (simulates 3 nodes failing)
Fleet.trigger_random_failures(nodes, 3)

# Stop all simulated nodes
Fleet.stop_all(nodes)
```

### Testing Rollouts with the Simulator

1. Spawn a fleet of simulated nodes
2. Create and compile a bundle
3. Create a rollout targeting all nodes
4. Watch the rollout progress in the UI as simulated nodes apply the bundle
5. Set `failure_rate: 0.1` to test health gate failures and auto-rollback

## Service Topology

The topology view provides a visual representation of your service graph, showing how services, upstream groups, and targets relate to each other.

### What Topology Shows

- **Services** as nodes in the graph with their route paths
- **Upstream groups** linked to services that use them
- **Upstream targets** showing individual backend servers
- **Middlewares** attached to services
- **Auth policies** and **WAF policies** linked to services
- **Certificates** associated with services

### Accessing Topology

Navigate to your project and click **Topology** in the sidebar. The graph updates in real-time as you add or modify resources.

## Config Validation Rules

Projects can define custom validation rules that are checked during bundle compilation.

### Rule Types

#### Required Field

Ensures a specific field or block exists in the KDL configuration:

```json
{
  "rule_type": "required_field",
  "name": "Require rate limiting",
  "pattern": "rate_limit",
  "severity": "error"
}
```

#### Forbidden Pattern

Rejects configurations containing a regex pattern:

```json
{
  "rule_type": "forbidden_pattern",
  "name": "No debug mode",
  "pattern": "debug\\s+(true|enabled)",
  "severity": "error"
}
```

#### Allowed Pattern

Requires the configuration to match a regex pattern:

```json
{
  "rule_type": "allowed_pattern",
  "name": "Must have health check",
  "pattern": "health_check\\s+\\{",
  "severity": "warning"
}
```

#### Max Size

Limits the configuration file size:

```json
{
  "rule_type": "max_size",
  "name": "Config size limit",
  "config": {"max_bytes": 102400},
  "severity": "error"
}
```

#### JSON Schema

Validates the configuration against a JSON schema:

```json
{
  "rule_type": "json_schema",
  "name": "Schema compliance",
  "config": {
    "schema": {
      "type": "object",
      "required": ["route"]
    }
  },
  "severity": "error"
}
```

### Severity Levels

| Severity | Compilation Effect |
|----------|-------------------|
| `error` | Fails compilation |
| `warning` | Compilation succeeds with warnings |
| `info` | Informational only |

### Managing Rules

Rules are managed per project via the UI or API. Each rule can be independently enabled or disabled.

## Bundle Promotion Pipeline

Bundles progress through environments in a defined order:

### Promotion Flow

```
1. Bundle compiled
2. Promote to dev (ordinal 0)
   └── Deploy via rollout to dev nodes
3. Promote to staging (ordinal 1)
   └── Deploy via rollout to staging nodes
4. Promote to production (ordinal 2)
   └── Deploy via rollout to production nodes
```

### Promotion Rules

- Bundles must be promoted in ordinal order (can't skip environments)
- Each promotion creates a `BundlePromotion` record with who promoted and when
- A bundle can only be promoted to each environment once
- Use `promote_bundle_to_next` to automatically promote to the next environment

### Viewing Promotion History

Each bundle shows its promotion timeline: which environments it has been promoted to, by whom, and when.

## KDL Configuration Generation

When services, upstreams, certificates, and other resources are defined in the control plane, they are compiled into KDL (KNode Document Language) configuration for the Zentinel proxy.

### How It Works

The compiler:

1. Reads all enabled services for the project, ordered by position
2. Generates KDL `route` blocks with upstream, timeout, retry, cache, and other settings
3. Includes middleware configurations in the processing chain
4. References certificates by their slugs
5. Injects auth policy and WAF policy configurations
6. Includes internal CA certificates as extra files
7. Collects and includes plugin files

### Generated Structure

```kdl
// Generated from service "API Backend"
route "/api/*" {
  upstream "http://api.internal:8080"
  timeout 30
  retry {
    attempts 3
    backoff "exponential"
  }
  rate_limit {
    requests 100
    window "1m"
  }
}
```

## Risk Scoring Details

Every compiled bundle is automatically scored for risk by comparing it against the previous bundle.

### Risk Factors

| Factor | Risk Level | Detection |
|--------|-----------|-----------|
| Auth policy changed | High | Auth/authentication/authorization blocks differ |
| TLS config changed | High | TLS blocks differ |
| Upstream removed | Medium | Upstream blocks disappeared |
| Rate limit changed | Medium | Rate limit blocks differ |
| Many route changes | Medium | >10 routes added or removed |

### How Scores Are Used

- **Risk level** is displayed in the bundle list and detail views
- **Risk reasons** explain what triggered the assessment
- High-risk bundles may warrant additional review or approval before deployment
- Risk scores are included in notification payloads

## Troubleshooting

### Bundle Compilation Fails

**Symptom**: Bundle status stays at `compiling` or transitions to `failed`.

**Check**:
1. Ensure the `zentinel` binary is available at the configured `ZENTINEL_BINARY` path
2. Check the bundle's `error` field for validation messages
3. Review the Oban job logs for `CompileWorker` failures

### Nodes Not Appearing Online

**Symptom**: Registered nodes show as `offline` or `unknown`.

**Check**:
1. Verify the node can reach the control plane URL
2. Check the node's authentication (key or JWT)
3. Ensure heartbeats are being sent (check the heartbeat interval)
4. The staleness threshold is 120 seconds — nodes must heartbeat within this window

### Rollout Stuck

**Symptom**: Rollout stays in `running` but doesn't progress.

**Check**:
1. Verify target nodes are online and heartbeating
2. Check health gates — a failing gate will pause progression
3. Review the current step's state and any error messages
4. Check the `progress_deadline_seconds` — steps fail after this deadline
5. Look for the `RolloutTickWorker` in the Oban dashboard

### Drift Events Not Resolving

**Symptom**: Drift events remain active even though nodes are running the expected bundle.

**Check**:
1. Verify the node's `active_bundle_id` matches `expected_bundle_id`
2. The `DriftWorker` auto-resolves synchronized nodes on its next run (every 30 seconds)
3. If `drift_auto_remediation` is enabled, check that remediation rollouts are completing

### Notifications Not Delivered

**Symptom**: Events occur but no notifications are received.

**Check**:
1. Verify the notification channel is enabled and configured correctly
2. Test the channel using the test function
3. Check delivery attempt records for error messages
4. Review the dead-letter queue for failed deliveries
5. Ensure a notification rule exists with a matching event pattern

### Database Performance

**Check**:
1. Monitor Ecto query metrics via Prometheus (`ecto_query_total_time`)
2. Check the connection pool size (`POOL_SIZE` environment variable)
3. For large fleets, ensure metrics rollup and cleanup workers are running
4. Old heartbeat and event records are pruned automatically (1,000 heartbeats, 500 events per node)

### Memory Usage

**Check**:
1. Monitor BEAM VM metrics via Prometheus (`beam_memory_*`)
2. Large fleets with frequent heartbeats may need tuning of heartbeat intervals
3. Check for accumulating Oban jobs in the queue
4. The simulator spawns GenServer processes per node — stop unused simulators
