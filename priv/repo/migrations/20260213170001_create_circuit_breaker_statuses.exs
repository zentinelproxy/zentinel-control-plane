defmodule ZentinelCp.Repo.Migrations.CreateCircuitBreakerStatuses do
  use Ecto.Migration

  def change do
    create table(:circuit_breaker_statuses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :upstream_group_id,
          references(:upstream_groups, type: :binary_id, on_delete: :delete_all), null: false

      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :state, :string, default: "closed", null: false
      add :failure_count, :integer, default: 0
      add :success_count, :integer, default: 0
      add :last_failure_at, :utc_datetime
      add :last_success_at, :utc_datetime
      add :last_trip_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:circuit_breaker_statuses, [:upstream_group_id])
    create index(:circuit_breaker_statuses, [:node_id])
    create unique_index(:circuit_breaker_statuses, [:upstream_group_id, :node_id])
  end
end
