# Development

## Prerequisites

- Elixir 1.16+ / Erlang OTP 26+ (managed via [mise](https://mise.jdx.dev/))
- Docker — for MinIO (bundle storage)
- `zentinel` CLI binary — for configuration validation during bundle compilation

## Setup

```bash
git clone https://github.com/zentinelproxy/zentinel-control-plane.git
cd zentinel-control-plane

mise install          # Install Elixir/Erlang
mise run setup        # Fetch deps, create DB, migrate, seed
mise run dev          # Start dev server (localhost:4000)
```

Uses SQLite for database (zero config) and MinIO via `docker-compose.dev.yml` for bundle storage.

## Commands

| Command | Description |
|---------|-------------|
| `mise run dev` | Start Phoenix dev server with hot reload |
| `mise run test` | Full test suite |
| `mise run test:coverage` | Tests with coverage report |
| `mise run format` | Format code |
| `mise run lint` | Run Credo linter |
| `mise run check` | Format + lint + test |
| `mise run db:setup` | Create + migrate database |
| `mise run db:reset` | Drop + create + migrate |
| `mise run db:migrate` | Run pending migrations |
| `mise run console` | IEx console with app loaded |

## Project Structure

```
lib/
├── zentinel_cp/                    # Business logic contexts
│   ├── accounts/                   # Users, API keys, TOTP
│   ├── auth/                       # JWT signing keys, node tokens, SSO
│   ├── bundles/                    # Bundle lifecycle, compiler, signing, SBOM, diff
│   ├── nodes/                      # Node management, heartbeats, drift
│   ├── rollouts/                   # Rollout orchestration, tick worker, health gates
│   ├── services/                   # Route definitions, upstreams, certs, middleware
│   ├── waf/                        # WAF rules, policies, analytics
│   ├── orgs/                       # Multi-org support, memberships
│   ├── projects/                   # Project/tenant management
│   ├── analytics.ex                # Request/WAF analytics
│   ├── observability.ex            # SLOs, alerts, metrics
│   ├── notifications.ex            # Notification channels + routing
│   ├── events.ex                   # Event pub/sub system
│   ├── secrets.ex                  # Encrypted secrets vault
│   ├── simulator.ex                # Fleet simulator (GenServer)
│   ├── application.ex              # OTP supervisor tree
│   ├── repo.ex                     # Ecto repository
│   └── release.ex                  # Migration helper for releases
└── zentinel_cp_web/                # Phoenix web layer
    ├── router.ex                   # Route definitions
    ├── controllers/api/            # REST API controllers
    ├── live/                       # LiveView pages
    ├── plugs/                      # Auth, API auth, node auth, scopes, rate limit
    ├── components/                 # UI components
    └── graphql/                    # Absinthe schema + resolvers
```

## Architecture Patterns

### Contexts

Each context module is a facade for a domain area. Contexts own their schemas and encapsulate all business logic.

```elixir
# Good: call the context
ZentinelCp.Bundles.create_bundle(project, attrs)

# Bad: reach into schemas directly
ZentinelCp.Bundles.Bundle.changeset(%Bundle{}, attrs) |> Repo.insert()
```

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Context | `ZentinelCp.<Domain>` | `ZentinelCp.Nodes` |
| Schema | `ZentinelCp.<Domain>.<Entity>` | `ZentinelCp.Nodes.Node` |
| Worker | `ZentinelCp.<Domain>.<Name>Worker` | `ZentinelCp.Rollouts.TickWorker` |
| LiveView | `ZentinelCpWeb.<Domain>Live.Index` | `ZentinelCpWeb.NodesLive.Index` |
| Plug | `ZentinelCpWeb.Plugs.<Name>` | `ZentinelCpWeb.Plugs.Auth` |
| Controller | `ZentinelCpWeb.Api.<Name>Controller` | `ZentinelCpWeb.Api.NodeController` |

### Code Style

- Use `with` for happy-path pipelines
- Use `TypedStruct` for complex structs
- Prefer explicit function heads over guards
- Keep LiveViews thin — delegate to contexts
- Audit all mutations — no silent state changes
- Handle errors explicitly — no silent failures

## Database

| Environment | Adapter | Notes |
|-------------|---------|-------|
| Dev/Test | `Ecto.Adapters.SQLite3` | Zero config, file-based |
| Production | `Ecto.Adapters.Postgres` | `DATABASE_URL` env var |

Selected at compile time: `config :zentinel_cp, :ecto_adapter`.

## Background Jobs

[Oban](https://hexdocs.pm/oban/) with three queues:

| Queue | Concurrency | Workers |
|-------|-------------|---------|
| `default` | 10 | CompileWorker, StalenessWorker, GCWorker, DriftWorker, SliWorker, AlertEvaluator, RollupWorker, WafBaselineWorker, WafAnomalyWorker |
| `rollouts` | 5 | RolloutTickWorker, SchedulerWorker |
| `maintenance` | 2 | Cleanup and maintenance jobs |

Dev uses `Oban.Engines.Lite` (SQLite), production uses `Oban.Engines.Basic` (PostgreSQL).

## Testing

Test-first approach, especially for domain logic.

```bash
mise run test                    # All tests
mise run test:coverage           # With coverage
mix test test/zentinel_cp/       # Context tests only
mix test test/zentinel_cp_web/   # Web layer tests only
```

Guidelines:
- Write tests first for domain logic
- Use contexts in tests (don't bypass with direct Repo calls)
- Test business rules, not implementation details
- Audit log assertions for mutation tests

## GraphQL

Absinthe schema at `POST /api/v1/graphql`. Supports queries, mutations, and subscriptions.

**GraphiQL IDE**: `/dev/graphiql` (development only).

## Fleet Simulator

GenServer-based node fleet simulator for testing rollouts without real proxy nodes.

- Simulates node registration, heartbeats, bundle polling
- Configurable fleet size and behavior
- Accessible via the web UI
- Useful for testing rollout strategies and health gate logic
