defmodule ZentinelCp.Repo.Migrations.CreatePolicyInfrastructure do
  use Ecto.Migration

  def change do
    create table(:policies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :policy_type, :string, null: false
      add :expression, :text, null: false
      add :enforcement, :string, null: false, default: "enforce"
      add :enabled, :boolean, null: false, default: true
      add :severity, :string, null: false, default: "warning"
      add :version, :integer, null: false, default: 1
      add :labels, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:policies, [:project_id])
    create unique_index(:policies, [:project_id, :name])

    create table(:policy_violations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :policy_id, references(:policies, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :action, :string, null: false
      add :message, :text
      add :context, :map, default: %{}
      add :dry_run, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:policy_violations, [:policy_id])
    create index(:policy_violations, [:project_id])
    create index(:policy_violations, [:resource_type])
  end
end
