defmodule ZentinelCp.Repo.Migrations.CreateRolloutTemplates do
  use Ecto.Migration

  def change do
    create table(:rollout_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :string
      add :is_default, :boolean, null: false, default: false

      # Templatable rollout configuration
      add :target_selector, :map
      add :strategy, :string, default: "rolling"
      add :batch_size, :integer, default: 1
      add :max_unavailable, :integer, default: 0
      add :progress_deadline_seconds, :integer, default: 600
      add :health_gates, :map, default: %{"heartbeat_healthy" => true}

      add :created_by_id, :binary_id
      timestamps(type: :utc_datetime)
    end

    create index(:rollout_templates, [:project_id])
    create unique_index(:rollout_templates, [:project_id, :name])

    # Only one default per project
    create unique_index(:rollout_templates, [:project_id],
             where: "is_default = true",
             name: :rollout_templates_one_default_per_project
           )
  end
end
