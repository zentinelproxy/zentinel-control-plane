defmodule ZentinelCp.Repo.Migrations.CreateDiscoverySources do
  use Ecto.Migration

  def change do
    create table(:discovery_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false, default: "dns_srv"
      add :hostname, :string, null: false
      add :sync_interval_seconds, :integer, default: 60
      add :auto_sync, :boolean, default: true
      add :last_synced_at, :utc_datetime
      add :last_sync_status, :string, default: "pending"
      add :last_sync_error, :text
      add :last_sync_targets_count, :integer, default: 0

      add :upstream_group_id,
          references(:upstream_groups, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:discovery_sources, [:project_id])
    create unique_index(:discovery_sources, [:upstream_group_id])
  end
end
