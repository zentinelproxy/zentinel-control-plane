# Sentinel Control Plane Documentation

Sentinel Control Plane is a fleet management system for [Sentinel](https://sentinel.dev) reverse proxies. It provides centralized configuration management, safe rollout orchestration, node lifecycle tracking, and comprehensive observability for your proxy fleet.

## Quick Navigation

| Guide | Description |
|-------|-------------|
| [Getting Started](getting-started.md) | Install, configure, and deploy your first bundle |
| [Architecture](architecture.md) | System design, components, and data flow |
| [Core Concepts](core-concepts.md) | Orgs, projects, bundles, nodes, rollouts, environments |
| [Configuration Management](configuration-management.md) | Services, upstreams, TLS, middlewares, plugins |
| [Deployment & Rollouts](deployment-and-rollouts.md) | Strategies, health gates, approvals, freeze windows |
| [Security](security.md) | WAF, auth policies, signing keys, API keys, SSO |
| [Observability](observability.md) | SLOs, alerting, analytics, Prometheus, OpenTelemetry |
| [Integrations](integrations.md) | GitOps, notifications, GraphQL, developer portal |
| [Node Management](node-management.md) | Registration, heartbeats, groups, drift detection |
| [Operations](operations.md) | Users, orgs, audit logs, environments, background jobs |
| [API Reference](api-reference.md) | REST API, Node API, GraphQL, authentication |
| [Advanced Topics](advanced-topics.md) | Simulator, topology, validation rules, troubleshooting |

## Common Tasks

**I want to...**

- **Set up a new project** — [Getting Started](getting-started.md)
- **Configure proxy routes** — [Configuration Management > Services](configuration-management.md#services)
- **Deploy a configuration change** — [Deployment & Rollouts](deployment-and-rollouts.md#creating-a-rollout)
- **Add a new proxy node** — [Node Management > Registration](node-management.md#node-registration)
- **Set up TLS certificates** — [Configuration Management > Certificates](configuration-management.md#tls-certificates)
- **Enable WAF protection** — [Security > WAF](security.md#web-application-firewall)
- **Create an SLO** — [Observability > SLOs](observability.md#service-level-objectives)
- **Set up Slack notifications** — [Integrations > Notifications](integrations.md#notification-channels)
- **Connect a GitHub repo** — [Integrations > GitOps](integrations.md#gitops-webhooks)
- **Create an API key** — [API Reference > Authentication](api-reference.md#api-key-authentication)
- **Review audit logs** — [Operations > Audit Logging](operations.md#audit-logging)
- **Simulate a fleet** — [Advanced Topics > Simulator](advanced-topics.md#node-fleet-simulator)

## System Requirements

- **Elixir** 1.16+ and **Erlang/OTP** 26+
- **PostgreSQL** 15+ (production) or **SQLite** (development)
- **S3-compatible storage** (MinIO for development, AWS S3 for production)
- **Sentinel CLI** binary (`sentinel`) for bundle compilation
