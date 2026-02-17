defmodule ZentinelCp.Repo.Migrations.CreateObservabilityInfrastructure do
  use Ecto.Migration

  def change do
    # SLO definitions
    create table(:slos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false
      add :description, :text
      add :sli_type, :string, null: false
      add :target, :float, null: false
      add :window_days, :integer, null: false, default: 30
      add :enabled, :boolean, null: false, default: true
      add :burn_rate, :float
      add :error_budget_remaining, :float
      add :last_computed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:slos, [:project_id])
    create index(:slos, [:service_id])
    create unique_index(:slos, [:project_id, :name])

    # Alert rules
    create table(:alert_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :rule_type, :string, null: false
      add :condition, :map, null: false
      add :severity, :string, null: false, default: "warning"
      add :for_seconds, :integer, null: false, default: 0
      add :channel_ids, {:array, :binary_id}, default: []
      add :enabled, :boolean, null: false, default: true
      add :silenced_until, :utc_datetime
      add :labels, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:alert_rules, [:project_id])
    create unique_index(:alert_rules, [:project_id, :name])

    # Alert states (firing/resolved history)
    create table(:alert_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :alert_rule_id, references(:alert_rules, type: :binary_id, on_delete: :delete_all),
        null: false

      add :state, :string, null: false, default: "inactive"
      add :value, :float
      add :started_at, :utc_datetime
      add :firing_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :acknowledged_by, :binary_id
      add :acknowledged_at, :utc_datetime
      add :notification_sent, :boolean, default: false
      add :fingerprint, :string

      timestamps(type: :utc_datetime)
    end

    create index(:alert_states, [:alert_rule_id])
    create index(:alert_states, [:state])
    create index(:alert_states, [:fingerprint])

    # Metric rollups (hourly/daily aggregates)
    create table(:metric_rollups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period, :string, null: false
      add :period_start, :utc_datetime, null: false
      add :request_count, :integer, default: 0
      add :error_count, :integer, default: 0
      add :latency_p50_ms, :integer
      add :latency_p95_ms, :integer
      add :latency_p99_ms, :integer
      add :bandwidth_in_bytes, :bigint, default: 0
      add :bandwidth_out_bytes, :bigint, default: 0
      add :status_2xx, :integer, default: 0
      add :status_3xx, :integer, default: 0
      add :status_4xx, :integer, default: 0
      add :status_5xx, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:metric_rollups, [:service_id])
    create index(:metric_rollups, [:project_id])
    create unique_index(:metric_rollups, [:service_id, :period, :period_start])
  end
end
