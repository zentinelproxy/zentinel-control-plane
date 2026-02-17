defmodule ZentinelCp.Repo.Migrations.AddDriftSeverity do
  use Ecto.Migration

  def change do
    alter table(:drift_events) do
      add :severity, :string, default: "medium"
      add :diff_stats, :map
    end

    create index(:drift_events, [:project_id, :severity])
  end
end
