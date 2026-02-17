defmodule ZentinelCp.Repo.Migrations.CreateUpstreamGroups do
  use Ecto.Migration

  def change do
    create table(:upstream_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :algorithm, :string, default: "round_robin"
      add :sticky_sessions, :map, default: %{}
      add :health_check, :map, default: %{}
      add :circuit_breaker, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:upstream_groups, [:project_id])
    create unique_index(:upstream_groups, [:project_id, :slug])

    create table(:upstream_targets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :upstream_group_id,
          references(:upstream_groups, type: :binary_id, on_delete: :delete_all),
          null: false

      add :host, :string, null: false
      add :port, :integer, null: false
      add :weight, :integer, default: 100
      add :max_connections, :integer
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:upstream_targets, [:upstream_group_id])

    alter table(:services) do
      add :upstream_group_id,
          references(:upstream_groups, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
