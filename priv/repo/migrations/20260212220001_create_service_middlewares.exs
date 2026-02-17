defmodule ZentinelCp.Repo.Migrations.CreateServiceMiddlewares do
  use Ecto.Migration

  def change do
    create table(:service_middlewares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false, default: 0
      add :enabled, :boolean, default: true
      add :config_override, :map, default: %{}

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all),
        null: false

      add :middleware_id, references(:middlewares, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:service_middlewares, [:service_id, :middleware_id])
    create index(:service_middlewares, [:service_id])
  end
end
