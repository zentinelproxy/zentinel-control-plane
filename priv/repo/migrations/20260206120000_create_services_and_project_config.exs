defmodule ZentinelCp.Repo.Migrations.CreateServicesAndProjectConfig do
  use Ecto.Migration

  def change do
    create table(:services, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :enabled, :boolean, default: true, null: false
      add :position, :integer, default: 0, null: false
      add :route_path, :string, null: false
      add :upstream_url, :string
      add :respond_status, :integer
      add :respond_body, :string
      add :timeout_seconds, :integer
      add :retry, :map, default: %{}
      add :cache, :map, default: %{}
      add :rate_limit, :map, default: %{}
      add :health_check, :map, default: %{}
      add :headers, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:services, [:project_id])
    create unique_index(:services, [:project_id, :slug])
    create index(:services, [:project_id, :position])

    create table(:project_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :log_level, :string, default: "info"
      add :metrics_port, :integer, default: 9090
      add :custom_settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_configs, [:project_id])
  end
end
