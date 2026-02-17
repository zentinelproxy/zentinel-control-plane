defmodule ZentinelCp.Repo.Migrations.CreateMiddlewares do
  use Ecto.Migration

  def change do
    create table(:middlewares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :middleware_type, :string, null: false
      add :config, :map, default: %{}
      add :enabled, :boolean, default: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:middlewares, [:project_id])
    create unique_index(:middlewares, [:project_id, :slug])
  end
end
