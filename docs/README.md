# Zentinel Control Plane

Fleet management control plane for [Zentinel](https://zentinel.dev) reverse proxies — centralized config compilation, rollout orchestration, node lifecycle, and observability.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Runtime | Elixir 1.16+ / Erlang OTP 26+ |
| Web | Phoenix 1.8, LiveView 1.1 |
| Background Jobs | Oban 2.19 |
| Database | PostgreSQL 15+ (prod), SQLite (dev) via Ecto |
| Object Storage | S3-compatible (AWS S3 prod, MinIO dev) |
| GraphQL | Absinthe 1.7 |
| Auth | Argon2, Ed25519 (JOSE), TOTP, OIDC, SAML |
| Observability | PromEx (Prometheus), OpenTelemetry |
| Frontend | Tailwind CSS, esbuild |

## Documentation

| Document | Contents |
|----------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, components, data flow, background jobs |
| [GETTING-STARTED.md](GETTING-STARTED.md) | Install, default credentials, first project, first rollout |
| [API.md](API.md) | REST API, Node API, GraphQL, curl examples |
| [AUTHENTICATION.md](AUTHENTICATION.md) | Web sessions, API keys, node auth, SSO, MFA, roles |
| [CONFIGURATION.md](CONFIGURATION.md) | Services, upstreams, TLS, middlewares, env vars |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Docker, production setup, rollout strategies, health gates |
| [SECURITY.md](SECURITY.md) | WAF, auth policies, bundle signing, encryption at rest |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Prometheus, SLOs, alerts, tracing, drift, notifications |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Building, testing, code style, project structure |

## Quick Reference

| I want to... | Go to |
|--------------|-------|
| Run locally with Docker | [GETTING-STARTED.md § Docker Compose](GETTING-STARTED.md#docker-compose) |
| Find the default login credentials | [GETTING-STARTED.md § Default Credentials](GETTING-STARTED.md#default-credentials) |
| Set up local dev (hot reload) | [GETTING-STARTED.md § Local Development](GETTING-STARTED.md#local-development) |
| Define proxy routes | [CONFIGURATION.md § Services](CONFIGURATION.md#services) |
| Compile a config bundle | [API.md § Create Bundle](API.md#create-bundle) |
| Deploy a bundle to nodes | [DEPLOYMENT.md § Rollout Strategies](DEPLOYMENT.md#rollout-strategies) |
| Register a proxy node | [API.md § Register Node](API.md#register-node) |
| Create a scoped API key | [AUTHENTICATION.md § API Key Authentication](AUTHENTICATION.md#api-key-authentication) |
| Set up canary deployments | [DEPLOYMENT.md § Canary](DEPLOYMENT.md#canary) |
| Configure TLS certificates | [CONFIGURATION.md § TLS Certificates](CONFIGURATION.md#tls-certificates) |
| Enable WAF protection | [SECURITY.md § WAF](SECURITY.md#web-application-firewall) |
| Set up Slack alerts | [OBSERVABILITY.md § Notification Channels](OBSERVABILITY.md#notification-channels) |
| Connect a GitHub repo (GitOps) | [CONFIGURATION.md § GitOps Integration](CONFIGURATION.md#gitops-integration) |
| Scrape Prometheus metrics | [OBSERVABILITY.md § Prometheus](OBSERVABILITY.md#prometheus-metrics) |
| Configure SSO | [AUTHENTICATION.md § SSO](AUTHENTICATION.md#sso-integration) |
| Contribute to the project | [DEVELOPMENT.md](DEVELOPMENT.md) |

## System Requirements

| Requirement | Dev | Prod |
|-------------|-----|------|
| Elixir | 1.16+ | 1.16+ |
| Erlang/OTP | 26+ | 26+ |
| Database | SQLite (zero config) | PostgreSQL 15+ |
| Object Storage | MinIO (docker-compose.dev.yml) | AWS S3 or S3-compatible |
| `zentinel` CLI | Required for bundle compilation | Required |
| Docker | Optional (for MinIO) | Optional (containerized deploy) |
