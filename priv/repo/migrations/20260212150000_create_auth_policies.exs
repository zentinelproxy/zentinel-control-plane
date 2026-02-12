defmodule SentinelCp.Repo.Migrations.CreateAuthPolicies do
  use Ecto.Migration

  def change do
    create table(:auth_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :auth_type, :string, null: false
      add :config, :map, default: %{}
      add :enabled, :boolean, default: true, null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:auth_policies, [:project_id])
    create unique_index(:auth_policies, [:project_id, :slug])

    alter table(:services) do
      add :auth_policy_id, references(:auth_policies, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
