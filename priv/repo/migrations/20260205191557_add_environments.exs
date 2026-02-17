defmodule ZentinelCp.Repo.Migrations.AddEnvironments do
  use Ecto.Migration

  def change do
    # Environments table
    create table(:environments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :color, :string, default: "#6366f1"
      add :ordinal, :integer, null: false, default: 0
      add :settings, :map, default: %{}

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:environments, [:project_id, :slug])
    create index(:environments, [:project_id, :ordinal])

    # Add environment_id to nodes
    alter table(:nodes) do
      add :environment_id, references(:environments, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:nodes, [:environment_id])

    # Add environment_id to rollouts
    alter table(:rollouts) do
      add :environment_id, references(:environments, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:rollouts, [:environment_id])

    # Bundle promotions table - tracks which environments a bundle has been promoted to
    create table(:bundle_promotions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bundle_id, references(:bundles, type: :binary_id, on_delete: :delete_all), null: false

      add :environment_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :promoted_by_id, :binary_id
      add :promoted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bundle_promotions, [:bundle_id, :environment_id])
    create index(:bundle_promotions, [:environment_id])
  end
end
