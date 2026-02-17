defmodule ZentinelCp.Repo.Migrations.AddAdvancedDeploymentFeatures do
  use Ecto.Migration

  def change do
    # Promotion rules for cross-environment automation
    create table(:promotion_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_env_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_env_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :auto_promote, :boolean, default: false
      add :delay_minutes, :integer, default: 0
      add :conditions, :map, default: %{}
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:promotion_rules, [:project_id])
    create unique_index(:promotion_rules, [:project_id, :source_env_id, :target_env_id])

    # Freeze windows
    create table(:freeze_windows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :environment_id, references(:environments, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :reason, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:freeze_windows, [:project_id])
    create index(:freeze_windows, [:starts_at, :ends_at])

    # Add canary analysis fields to rollouts
    alter table(:rollouts) do
      add :canary_analysis_config, :map
      add :canary_analysis_results, :map
      add :deployment_slot, :string
      add :validation_period_seconds, :integer, default: 300
    end
  end
end
