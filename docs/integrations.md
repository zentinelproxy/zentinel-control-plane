# Integrations

This guide covers external integrations: GitOps webhooks, notification channels, GraphQL API, and the developer portal.

## GitOps Webhooks

The control plane supports automatic bundle creation triggered by Git push events.

### Supported Providers

| Provider | Endpoint | Verification |
|----------|----------|--------------|
| GitHub | `POST /api/v1/webhooks/github` | HMAC-SHA256 (`X-Hub-Signature-256`) |
| GitLab | `POST /api/v1/webhooks/gitlab` | Token comparison (`X-Gitlab-Token`) |
| Bitbucket | `POST /api/v1/webhooks/bitbucket` | Provider-specific |
| Gitea | `POST /api/v1/webhooks/gitea` | Provider-specific |
| Generic | `POST /api/v1/webhooks/generic` | Configurable HMAC header and algorithm |

### Setup

1. **Configure the project** with a Git repository:
   - Repository: `owner/repo` format (e.g., `acme/proxy-config`)
   - Branch: Target branch to watch (default: `main`)
   - Config path: Path to KDL configuration file (default: `sentinel.kdl`)

2. **Add a webhook** in your Git provider pointing to the appropriate endpoint.

3. **Set the webhook secret**:
   - GitHub: Set `GITHUB_WEBHOOK_SECRET` environment variable
   - GitLab: Configure token in the GitLab webhook settings
   - Generic: Configure HMAC secret in the provider settings

### Workflow

When a push event is received:

1. Verify the webhook signature
2. Parse the event to extract repository, branch, and commits
3. Match the repository and branch to a project
4. Fetch the KDL configuration file from the repository
5. Create a new bundle with the configuration source
6. Compilation runs in the background

Only pushes to the configured branch trigger bundle creation. Commits that don't modify the configuration file path are ignored.

### Webhook Events

The control plane records webhook events with type and payload for audit purposes. Each event is traced via OpenTelemetry when enabled.

## Notification Channels

Route operational events to external notification services.

### Channel Types

#### Slack

Send formatted messages to Slack channels using incoming webhooks.

**Configuration**:
```json
{"webhook_url": "https://hooks.slack.com/services/T.../B.../xxx"}
```

Messages use Slack Block Kit format with event title, type, timestamp, and payload details.

#### PagerDuty

Trigger and resolve incidents via PagerDuty Events API v2.

**Configuration**:
```json
{"routing_key": "your-pagerduty-routing-key"}
```

Events are mapped to PagerDuty severities:
- `failed` events → "error"
- `drift` events → "warning"
- `security` events → "critical"
- Other events → "info"

Resolved/completed events automatically send "resolve" actions. Dedup key format: `sentinel-{event_type}-{project_id}`.

#### Microsoft Teams

Send messages to Teams channels using incoming webhooks with Adaptive Cards.

**Configuration**:
```json
{"webhook_url": "https://outlook.webhook.office.com/..."}
```

#### Email

Send notification emails via Swoosh.

**Configuration**:
```json
{"to": "ops@example.com", "from": "noreply@sentinel.example.com"}
```

#### Generic Webhook

Send signed JSON payloads to any HTTP endpoint.

**Configuration**:
```json
{"url": "https://example.com/webhook"}
```

The control plane generates an HMAC signing secret for each webhook channel. Payloads include:
- `event`: Event type
- `timestamp`: ISO 8601 timestamp
- `payload`: Event data
- `project_id`, `org_id`: Context identifiers

Signature headers:
- `x-sentinel-signature`: `t={unix_timestamp},v1={hmac_sha256_hex}`
- `x-sentinel-timestamp`: Unix timestamp

### Testing Channels

Test any channel by sending a synthetic `system.test` event:

```
POST: test_channel(channel)
```

This creates a real delivery attempt so you can verify the integration end-to-end.

## Notification Rules

Notification rules define which events are routed to which channels.

### Creating a Rule

| Property | Description |
|----------|-------------|
| `name` | Display name |
| `event_pattern` | Pattern to match event types |
| `channel_id` | Target notification channel |
| `filter` | Optional additional filters |

### Event Patterns

Patterns use a simple matching syntax:

| Pattern | Matches |
|---------|---------|
| `*` | All events |
| `rollout.*` | All rollout events |
| `rollout.completed` | Only rollout completion events |
| `security.*` | All security events |
| `drift.*` | All drift events |

### Event Types

| Event Type | When Emitted |
|------------|-------------|
| `rollout.started` | Rollout begins execution |
| `rollout.completed` | Rollout successfully finishes |
| `rollout.failed` | Rollout fails |
| `rollout.cancelled` | Rollout is cancelled |
| `rollout.paused` | Rollout is paused |
| `rollout.approved` | Rollout receives an approval |
| `rollout.rejected` | Rollout is rejected |
| `rollout.state_changed` | Any rollout state transition |
| `bundle.created` | New bundle created |
| `bundle.promoted` | Bundle promoted to an environment |
| `bundle.revoked` | Bundle revoked |
| `node.registered` | New node registers |
| `node.deregistered` | Node removed |
| `drift.detected` | Configuration drift detected |
| `drift.resolved` | Drift resolved |
| `drift.threshold_exceeded` | Too many nodes drifted |
| `secret.rotated` | Secret value updated |
| `secret.accessed` | Secret value accessed |
| `security.alert_fired` | Alert rule transitions to firing |
| `security.waf_anomaly` | WAF anomaly detected |
| `security.auth_failed` | Authentication failure |
| `system.test` | Channel test event |

## Delivery Tracking

Every notification delivery is tracked with:

| Property | Description |
|----------|-------------|
| `status` | `pending`, `delivering`, `delivered`, `failed`, `dead_letter`, `skipped` |
| `http_status` | HTTP response status code |
| `latency_ms` | Delivery latency |
| `error` | Error message (if failed) |
| `attempt_number` | Current attempt (1-based) |
| `request_body` | Sent payload (truncated to 10 KB) |
| `response_body` | Response body (truncated to 10 KB) |

### Retry Logic

Failed deliveries are retried with exponential backoff:

| Attempt | Approximate Delay |
|---------|-------------------|
| 1 | Immediate |
| 2 | ~1 minute |
| 3 | ~2 minutes |
| 4 | ~4 minutes |
| 5 | ~8 minutes |
| 6 | ~16 minutes |
| 7 | ~32 minutes |
| 8 | ~1 hour |
| 9 | ~2 hours |
| 10 | ~4 hours |

Random jitter (25% of base delay) is added to prevent thundering herds.

After 10 attempts, the delivery moves to the **dead-letter queue**. Dead-letter deliveries can be manually retried from the Notifications UI.

### Delivery Stats

View aggregate delivery statistics over a time window:
- Delivered count
- Failed count
- Dead-letter count
- Pending count

## GraphQL API

The control plane exposes a GraphQL endpoint at `POST /api/v1/graphql`.

### Authentication

GraphQL requests use the same API key authentication as the REST API:

```
Authorization: Bearer YOUR_API_KEY
```

### Subscriptions

The GraphQL API supports Absinthe subscriptions for real-time updates. Alert state changes are published via subscriptions, enabling real-time dashboard integrations.

## Developer Portal

Projects can expose a developer portal for API documentation and exploration.

### Configuration

Enable the portal in project settings:

| Setting | Description |
|---------|-------------|
| `portal_enabled` | Enable/disable the portal |
| `portal_access` | Access level: `"disabled"`, `"public"`, or `"authenticated"` |
| `portal_title` | Portal page title |
| `portal_description` | Portal description text |
| `portal_logo_url` | Logo image URL |

### Access Control

| Level | Description |
|-------|-------------|
| `disabled` | Portal returns 404 |
| `public` | Anyone can access |
| `authenticated` | Requires session or API key authentication |

### Portal Content

The developer portal displays:

- API documentation generated from OpenAPI specs attached to services
- Available endpoints with methods, descriptions, and parameters
- Authentication requirements per endpoint
- Interactive API exploration (when authenticated)

Attach an OpenAPI spec to a service and configure the `openapi_path` to serve it through the portal.
