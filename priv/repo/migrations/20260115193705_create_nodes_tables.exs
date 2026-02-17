defmodule ZentinelCp.Repo.Migrations.CreateNodesTables do
  use Ecto.Migration

  def change do
    # Nodes table
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :node_key_hash, :string, null: false
      add :labels, :map, default: %{}
      add :capabilities, {:array, :string}, default: []
      add :version, :string
      add :ip, :string
      add :hostname, :string
      add :metadata, :map, default: %{}
      add :status, :string, null: false, default: "unknown"
      add :last_seen_at, :utc_datetime
      add :registered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:nodes, [:project_id, :name])
    create index(:nodes, [:project_id])
    create index(:nodes, [:status])
    create index(:nodes, [:last_seen_at])

    # Node heartbeats table (for historical tracking)
    create table(:node_heartbeats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :health, :map, default: %{}
      add :metrics, :map, default: %{}
      add :active_bundle_id, :binary_id
      add :staged_bundle_id, :binary_id

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:node_heartbeats, [:node_id])
    create index(:node_heartbeats, [:inserted_at])

    # Audit logs table
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, :binary_id
      # user, api_key, system, node
      add :actor_type, :string, null: false
      add :actor_id, :binary_id
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :changes, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:project_id])
    create index(:audit_logs, [:actor_type, :actor_id])
    create index(:audit_logs, [:resource_type, :resource_id])
    create index(:audit_logs, [:inserted_at])
  end
end
