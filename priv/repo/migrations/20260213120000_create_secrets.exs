defmodule SentinelCp.Repo.Migrations.CreateSecrets do
  use Ecto.Migration

  def change do
    create table(:secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :encrypted_value, :binary, null: false
      add :description, :string
      add :environment, :string
      add :last_rotated_at, :utc_datetime
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:secrets, [:project_id])
    create unique_index(:secrets, [:project_id, :name, :environment], name: :secrets_project_name_env_index)
  end
end
