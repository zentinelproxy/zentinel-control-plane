defmodule ZentinelCp.Repo.Migrations.AddNodeEventsAndRuntimeConfig do
  use Ecto.Migration

  def change do
    # Node events table (structured event log per node)
    create table(:node_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :severity, :string, null: false, default: "info"
      add :message, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:node_events, [:node_id, :inserted_at])

    # Node runtime configs table (latest KDL config per node, upserted)
    create table(:node_runtime_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :config_kdl, :text, null: false
      add :config_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_runtime_configs, [:node_id])
  end
end
