# Zentinel Control Plane (Elixir) — Implementation Roadmap

> Refined implementation plan for the Zentinel Control Plane in Elixir/Phoenix.

## 0) Goals, Non-goals, Principles

### Goals
- Declarative desired state → compiled bundles → safe rollout → verifiable activation
- Pull-based distribution (v1) with optional push later
- Multi-tenant-ready foundation (even if single-tenant at first)
- First-class: rollback, health gates, auditability, signing, drift detection
- "Sleepable ops": deterministic behaviors, safe defaults, clear failure modes

### Non-goals (v1)
- Full UI polish (functional LiveView screens, not design perfection)
- Complex RBAC hierarchies (start with roles: admin/operator/reader)
- Full secret management (integrate with Vault/KMS later; v1 uses secret references)

### Principles
- Nodes are dumb: they pull bundles, verify, stage, activate, report
- Control plane is strict: config compiles into immutable artifacts
- Everything is versioned and auditable: bundles, rollouts, policies, changesets
- Fail closed: invalid config never ships; suspect nodes don't receive rollouts

---

## 1) System Architecture

### Components
1. **Phoenix Control Plane API + UI**
   - REST API for nodes and operators
   - LiveView for operator workflows
2. **Compiler Service (Hybrid)**
   - Uses `zentinel validate` for validation (shells out to Rust binary)
   - Elixir handles bundling, hashing, signing, storage
3. **Bundle Store**
   - S3/MinIO (always — MinIO for dev, S3/compatible for prod)
4. **Database**
   - SQLite (dev/test), PostgreSQL (production)
5. **Telemetry + Metrics**
   - Prometheus endpoint, structured logs, OpenTelemetry ready

### Data Flow (v1: pull)
```
Desired state updated (via API or GitOps webhook)
    → Compiler validates config via `zentinel validate`
    → Produces Bundle (tar.zst)
    → Stored in MinIO/S3
    → Rollout controller assigns target nodes
    → Nodes poll and download bundle
    → Nodes activate
    → Nodes report status
    → Rollout progresses/pauses/rolls back
```

---

## 2) Repository Structure

Single Phoenix application with clear module boundaries:

```
zentinel-cp/
├── .claude/
│   └── CONTROL_PLANE_ROADMAP.md
├── lib/
│   ├── zentinel_cp/
│   │   ├── bundles/          # Bundle lifecycle
│   │   ├── compiler/         # Compilation pipeline
│   │   ├── nodes/            # Node management
│   │   ├── rollouts/         # Rollout orchestration
│   │   ├── projects/         # Project/tenant management
│   │   ├── accounts/         # Users, API keys, auth
│   │   ├── audit/            # Audit logging
│   │   ├── storage/          # S3/MinIO abstraction
│   │   └── simulator/        # Node simulator for testing
│   └── zentinel_cp_web/
│       ├── controllers/      # REST API
│       ├── live/             # LiveView pages
│       └── components/       # UI components
├── priv/
│   └── repo/migrations/
├── test/
├── config/
├── docker/
├── mise.toml
└── mix.exs
```

---

## 3) Domain Model (Refined)

### v1: Single implicit org, Projects only
```elixir
# Core entities
Project          # Tenant boundary
Node             # Zentinel instance
NodeGroup        # Label selector or explicit set
DesiredConfig    # Raw inputs (manifests)
Bundle           # Compiled immutable artifact
Rollout          # Plan to apply bundle to targets
RolloutStep      # Batch within rollout
NodeBundleStatus # Per-node: staged/active/failed
AuditLog         # Who did what
User             # Operator accounts
ApiKey           # Programmatic access
```

### v1.1: Add multi-org
```elixir
Org              # Organization boundary
# Project gains org_id foreign key
```

---

## 4) Bundle Format (Immutable Artifact)

### v1 Minimal Bundle
```
bundle.tar.zst
├── manifest.json    # Metadata + hashes
├── config.json      # Merged zentinel config
└── checksums.txt    # Per-file SHA256
```

### manifest.json fields
```json
{
  "bundle_id": "<sha256 of canonical manifest + payload>",
  "schema_version": "1",
  "created_at": "2025-01-15T00:00:00Z",
  "project_id": "uuid",
  "source": {
    "type": "api|git",
    "ref": "git sha or request id"
  },
  "payload_hashes": {
    "config.json": "sha256:..."
  },
  "compat": {
    "zentinel_min_version": "2025.01"
  },
  "risk": "low|medium|high",
  "risk_reasons": []
}
```

### v1.1 additions
- `signature.sig` (Ed25519)
- `SBOM.json` (optional)

---

## 5) Database Schema

### Core Tables
```sql
-- Projects (v1: single implicit org)
CREATE TABLE projects (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  settings JSONB DEFAULT '{}',
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Users
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  hashed_password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'reader', -- admin, operator, reader
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- API Keys
CREATE TABLE api_keys (
  id UUID PRIMARY KEY,
  project_id UUID REFERENCES projects(id),
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  scopes TEXT[] DEFAULT '{}',
  last_used_at TIMESTAMP,
  revoked_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL
);

-- Nodes
CREATE TABLE nodes (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  name TEXT NOT NULL,
  node_key_hash TEXT NOT NULL,
  labels JSONB DEFAULT '{}',
  capabilities TEXT[] DEFAULT '{}',
  version TEXT,
  ip TEXT,
  metadata JSONB DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'unknown', -- online, offline, unknown
  last_seen_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(project_id, name)
);

-- Desired Configs
CREATE TABLE desired_configs (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  source_type TEXT NOT NULL, -- api, git
  source_ref TEXT,
  raw JSONB NOT NULL,
  compiled_at TIMESTAMP,
  last_bundle_id UUID,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Bundles
CREATE TABLE bundles (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  bundle_id TEXT NOT NULL, -- content hash
  schema_version INTEGER NOT NULL DEFAULT 1,
  manifest JSONB NOT NULL,
  artifact_url TEXT NOT NULL,
  artifact_hash TEXT NOT NULL,
  signature_url TEXT,
  status TEXT NOT NULL DEFAULT 'ready', -- ready, deprecated, revoked
  risk TEXT NOT NULL DEFAULT 'low',
  risk_reasons TEXT[] DEFAULT '{}',
  created_by_id UUID,
  inserted_at TIMESTAMP NOT NULL,
  UNIQUE(project_id, bundle_id)
);

-- Rollouts
CREATE TABLE rollouts (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  bundle_id UUID NOT NULL REFERENCES bundles(id),
  target_selector JSONB NOT NULL, -- {"labels": {"env": "prod"}}
  strategy TEXT NOT NULL DEFAULT 'rolling', -- rolling, canary, blue_green
  batch_size INTEGER NOT NULL DEFAULT 1,
  max_unavailable INTEGER NOT NULL DEFAULT 0,
  progress_deadline_seconds INTEGER NOT NULL DEFAULT 600,
  health_gates JSONB DEFAULT '{}',
  state TEXT NOT NULL DEFAULT 'pending', -- pending, running, paused, failed, completed, rolled_back
  created_by_id UUID,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Rollout Steps
CREATE TABLE rollout_steps (
  id UUID PRIMARY KEY,
  rollout_id UUID NOT NULL REFERENCES rollouts(id),
  step_index INTEGER NOT NULL,
  node_ids UUID[] NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending', -- pending, running, completed, failed
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  error JSONB,
  UNIQUE(rollout_id, step_index)
);

-- Node Bundle Status
CREATE TABLE node_bundle_statuses (
  id UUID PRIMARY KEY,
  node_id UUID NOT NULL REFERENCES nodes(id),
  rollout_id UUID NOT NULL REFERENCES rollouts(id),
  bundle_id UUID NOT NULL REFERENCES bundles(id),
  state TEXT NOT NULL DEFAULT 'assigned', -- assigned, downloaded, staged, activated, verified, failed, rolled_back
  reason TEXT,
  staged_at TIMESTAMP,
  activated_at TIMESTAMP,
  verified_at TIMESTAMP,
  last_report_at TIMESTAMP,
  error JSONB,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(node_id, rollout_id)
);

-- Audit Logs
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  project_id UUID REFERENCES projects(id),
  actor_type TEXT NOT NULL, -- user, api_key, system, node
  actor_id UUID,
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  diff JSONB,
  metadata JSONB DEFAULT '{}',
  inserted_at TIMESTAMP NOT NULL
);
```

---

## 6) API Design

### Node Authentication
- Static node keys (v1): `X-Zentinel-Node-Key: <random>` stored hashed
- v1.1: Add JWT option for short-lived tokens

### Node Endpoints
```
POST   /api/v1/projects/:project/nodes/register
       → {node_id, node_token, poll_interval_s}

POST   /api/v1/nodes/:node_id/heartbeat
       ← {active_bundle_id, staged_bundle_id, health, metrics}

GET    /api/v1/nodes/:node_id/bundles/latest
       → {bundle_id, rollout_id, artifact_url, artifact_hash, poll_after_s}
       → {no_update: true, poll_after_s} if current

POST   /api/v1/nodes/:node_id/bundles/:bundle_id/staged
POST   /api/v1/nodes/:node_id/bundles/:bundle_id/activated
POST   /api/v1/nodes/:node_id/bundles/:bundle_id/verified
POST   /api/v1/nodes/:node_id/bundles/:bundle_id/failed
       ← {error, logs}
```

### Control Plane Endpoints (User/API Key auth)
```
# Projects
GET    /api/v1/projects
POST   /api/v1/projects
GET    /api/v1/projects/:id

# Nodes
GET    /api/v1/projects/:project/nodes
GET    /api/v1/projects/:project/nodes/:id

# Bundles
GET    /api/v1/projects/:project/bundles
GET    /api/v1/projects/:project/bundles/:id
POST   /api/v1/projects/:project/bundles/:id/revoke

# Desired Config + Compilation
POST   /api/v1/projects/:project/desired_config
POST   /api/v1/projects/:project/compile

# Rollouts
GET    /api/v1/projects/:project/rollouts
POST   /api/v1/projects/:project/rollouts
GET    /api/v1/rollouts/:id
POST   /api/v1/rollouts/:id/pause
POST   /api/v1/rollouts/:id/resume
POST   /api/v1/rollouts/:id/rollback

# Audit
GET    /api/v1/projects/:project/audit_logs
```

---

## 7) Compiler Pipeline (Hybrid Approach)

### Strategy
Use `zentinel validate` for validation, Elixir for bundling:

```elixir
defmodule ZentinelCp.Compiler do
  def compile(project, desired_config) do
    with {:ok, validated} <- validate_with_zentinel(desired_config),
         {:ok, bundle_content} <- build_bundle(project, validated),
         {:ok, hashes} <- compute_hashes(bundle_content),
         {:ok, manifest} <- build_manifest(project, hashes, desired_config),
         {:ok, archive} <- create_archive(manifest, bundle_content),
         {:ok, artifact_url} <- upload_to_storage(project, archive),
         {:ok, bundle} <- persist_bundle(project, manifest, artifact_url) do
      {:ok, bundle}
    end
  end

  defp validate_with_zentinel(config) do
    # Write config to temp file
    # Run: zentinel validate --json <temp_file>
    # Parse JSON output for errors/warnings
  end
end
```

### Risk Scoring (v1 minimal)
```elixir
defmodule ZentinelCp.Compiler.Risk do
  def score(prev_bundle, new_bundle) do
    reasons = []

    reasons = if changed_auth_policy?(prev_bundle, new_bundle),
      do: ["auth_policy_changed" | reasons], else: reasons

    reasons = if route_count_delta(prev_bundle, new_bundle) > 10,
      do: ["many_route_changes" | reasons], else: reasons

    level = cond do
      "auth_policy_changed" in reasons -> :high
      length(reasons) > 0 -> :medium
      true -> :low
    end

    {level, reasons}
  end
end
```

---

## 8) Rollout Controller

### Oban Jobs
```elixir
# Process rollout ticks
defmodule ZentinelCp.Rollouts.TickWorker do
  use Oban.Worker, queue: :rollouts, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rollout_id" => rollout_id}}) do
    ZentinelCp.Rollouts.Orchestrator.tick(rollout_id)
  end
end

# Mark stale nodes offline
defmodule ZentinelCp.Nodes.StalenessWorker do
  use Oban.Worker, queue: :maintenance

  @impl Oban.Worker
  def perform(_job) do
    ZentinelCp.Nodes.mark_stale_offline()
  end
end

# Clean old bundles
defmodule ZentinelCp.Bundles.GCWorker do
  use Oban.Worker, queue: :maintenance

  @impl Oban.Worker
  def perform(_job) do
    ZentinelCp.Bundles.garbage_collect()
  end
end
```

### State Machines
```
Rollout: pending → running → (paused | failed | completed | rolled_back)

NodeBundleStatus: assigned → staged → activated → verified
                                   ↘ failed
                                   ↘ rolled_back
```

### Health Gates (v1)
```elixir
defmodule ZentinelCp.Rollouts.HealthGates do
  def check(rollout, step) do
    nodes = get_step_nodes(step)

    # Gate 1: Node heartbeat fresh
    all_fresh? = Enum.all?(nodes, fn node ->
      DateTime.diff(DateTime.utc_now(), node.last_seen_at, :second) < 120
    end)

    # Gate 2: Node self-reported health OK
    all_healthy? = Enum.all?(nodes, &(&1.status == :online))

    cond do
      not all_fresh? -> {:fail, :stale_nodes}
      not all_healthy? -> {:fail, :unhealthy_nodes}
      true -> :pass
    end
  end
end
```

---

## 9) Node Simulator

### Purpose
- Test rollout logic without real Zentinel instances
- Load testing (simulate 100+ nodes)
- CI integration tests

### Implementation
```elixir
defmodule ZentinelCp.Simulator.Node do
  use GenServer

  defstruct [:id, :name, :project_id, :node_key, :current_bundle, :state, :config]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = %__MODULE__{
      name: opts[:name],
      project_id: opts[:project_id],
      node_key: generate_node_key(),
      state: :disconnected
    }

    # Register with control plane
    send(self(), :register)

    {:ok, state}
  end

  def handle_info(:register, state) do
    case register_node(state) do
      {:ok, node_id} ->
        schedule_heartbeat()
        {:noreply, %{state | id: node_id, state: :connected}}
      {:error, _} ->
        schedule_retry()
        {:noreply, state}
    end
  end

  def handle_info(:heartbeat, state) do
    send_heartbeat(state)
    check_for_bundle(state)
    schedule_heartbeat()
    {:noreply, state}
  end

  def handle_info({:apply_bundle, bundle_id}, state) do
    # Simulate download, stage, activate, verify
    Process.sleep(state.config.apply_delay_ms)

    case simulate_activation(state.config) do
      :ok ->
        report_verified(state, bundle_id)
        {:noreply, %{state | current_bundle: bundle_id}}
      {:error, reason} ->
        report_failed(state, bundle_id, reason)
        {:noreply, state}
    end
  end

  defp simulate_activation(config) do
    if :rand.uniform() < config.failure_rate do
      {:error, "simulated failure"}
    else
      :ok
    end
  end
end

defmodule ZentinelCp.Simulator.Fleet do
  @moduledoc "Spawn and manage multiple simulated nodes"

  def spawn_nodes(project_id, count, opts \\ []) do
    for i <- 1..count do
      ZentinelCp.Simulator.Node.start_link(
        name: "sim-node-#{i}",
        project_id: project_id,
        config: %{
          poll_interval_ms: opts[:poll_interval_ms] || 5_000,
          apply_delay_ms: opts[:apply_delay_ms] || 1_000,
          failure_rate: opts[:failure_rate] || 0.0
        }
      )
    end
  end
end
```

---

## 10) Security Model

### Transport
- TLS everywhere (HTTPS)
- mTLS optional later

### AuthN/AuthZ
- **Users**: email/password + Argon2, roles (admin/operator/reader)
- **API Keys**: scoped, hashed, revocable
- **Nodes**: static keys hashed in DB, revocable

### Audit Log
Log all mutations:
- Compilation events
- Rollout create/pause/resume/rollback
- Node registrations and revocations
- Bundle revocations
- User/API key changes

---

## 11) LiveView UI (v1 Screens)

### Required
- **Nodes List**: filter by label/status, show last_seen, active bundle
- **Node Detail**: history, current bundle, errors
- **Bundles List**: risk level, source ref, created time
- **Bundle Detail**: manifest, config preview
- **Rollouts List**: state, progress percentage
- **Rollout Detail**: steps, per-node status, pause/resume/rollback buttons
- **Audit Log**: filter by action, actor, time

### Deferred to v1.1
- Dashboard with metrics
- Diff viewer (prev bundle vs new)
- Config upload UI (API-only is fine for v1)

---

## 12) Testing Strategy

### Unit Tests
- Compiler validators
- Bundle hashing determinism
- Selector matching
- Rollout step planner

### Integration Tests
- Full rollout flow with simulated nodes
- Pause/resume/rollback scenarios
- Failure injection

### Property Tests
- Deterministic compilation (same input → same bundle_id)
- Rollout planner stable ordering

---

## 13) Implementation Phases

### Phase 1 — Skeleton + Nodes + Simulator
**Deliverables:**
- Phoenix app structure
- User auth (email/password)
- Project CRUD
- Node registration + heartbeat
- Node simulator (basic)
- LiveView: Nodes list + detail

**Acceptance:**
- Node can register, send heartbeats
- Simulator can spawn 10 nodes
- UI shows online/offline nodes

### Phase 2 — Bundles + Storage
**Deliverables:**
- MinIO integration
- Bundle storage + retrieval
- Bundle metadata API
- LiveView: Bundles list + detail

**Acceptance:**
- Bundle can be uploaded, stored, downloaded
- Nodes can fetch bundles via signed URL

### Phase 3 — Compiler
**Deliverables:**
- `zentinel validate` integration
- Bundle assembly (tar.zst)
- Hashing + manifest generation
- Risk scoring (basic)

**Acceptance:**
- POST desired_config → bundle created
- Bundle hash stable for same input

### Phase 4 — Rollouts
**Deliverables:**
- Rollout creation + planner
- Rollout tick worker (Oban)
- NodeBundleStatus tracking
- Health gates (basic)
- Pause/resume/rollback
- LiveView: Rollouts list + detail

**Acceptance:**
- Rollout progresses through batches
- Simulated nodes activate bundles
- Pause/rollback works

### Phase 5 — Security + Audit
**Deliverables:**
- API key management
- Bundle signing (Ed25519)
- Audit log for all mutations
- LiveView: Audit log

**Acceptance:**
- All changes audited
- Signed bundles verifiable

### Phase 6 — GitOps Integration (optional)
**Deliverables:**
- GitHub webhook receiver
- Auto-compile on push
- Source ref tracking

### Phase 7 — Production Hardening
**Deliverables:**
- Prometheus metrics
- Structured logging
- Dockerfile + docker-compose
- Health endpoints

---

## 14) Definition of Done (v1 GA)

- [ ] Deterministic bundle generation (same input → same bundle_id)
- [ ] Nodes can register, poll, download, activate, verify, report
- [ ] Rollouts batch safely with pause/rollback
- [ ] Offline nodes don't block rollouts indefinitely
- [ ] All mutations audited
- [ ] Bundle revocation prevents distribution
- [ ] Basic UI covers nodes/bundles/rollouts/audit
- [ ] Metrics endpoint functional
- [ ] Docker image builds and runs

---

## 15) Tech Stack Summary

| Component | Technology |
|-----------|------------|
| Language | Elixir 1.19.5, OTP 28 |
| Framework | Phoenix 1.8.3 |
| Real-time UI | LiveView 1.1 |
| Database (dev) | SQLite via ecto_sqlite3 |
| Database (prod) | PostgreSQL via postgrex |
| Background Jobs | Oban 2.19 |
| Object Storage | ExAws + S3/MinIO |
| Password Hashing | Argon2 |
| HTTP Client | Req |
| CSS | Tailwind 4 + DaisyUI |
| Task Runner | mise |

---

## References

- [Phoenix 1.8 Release](https://www.phoenixframework.org/blog/phoenix-1-8-released)
- [Oban Documentation](https://hexdocs.pm/oban/)
- [Elixir 1.19 Release](https://elixir-lang.org/blog/2025/10/16/elixir-v1-19-0-released/)
