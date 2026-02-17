defmodule ZentinelCp.Repo.Migrations.CreateDriftEvents do
  use Ecto.Migration

  def change do
    create table(:drift_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :expected_bundle_id, :binary_id, null: false
      add :actual_bundle_id, :binary_id
      add :detected_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime
      add :resolution, :string

      timestamps(type: :utc_datetime)
    end

    create index(:drift_events, [:node_id])
    create index(:drift_events, [:project_id])
    create index(:drift_events, [:detected_at])
    create index(:drift_events, [:resolved_at])
  end
end
