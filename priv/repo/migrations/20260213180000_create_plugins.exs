defmodule ZentinelCp.Repo.Migrations.CreatePlugins do
  use Ecto.Migration

  def change do
    create table(:plugins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :plugin_type, :string, null: false
      add :config_schema, :map, default: %{}
      add :default_config, :map, default: %{}
      add :enabled, :boolean, default: true
      add :public, :boolean, default: false
      add :author, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plugins, [:project_id, :slug])
    create index(:plugins, [:plugin_type])
    create index(:plugins, [:public])

    create table(:plugin_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plugin_id, references(:plugins, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :storage_key, :string, null: false
      add :checksum, :string, null: false
      add :file_size, :integer, null: false
      add :changelog, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plugin_versions, [:plugin_id, :version])
    create index(:plugin_versions, [:plugin_id])

    create table(:service_plugins, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plugin_id, references(:plugins, type: :binary_id, on_delete: :delete_all), null: false

      add :plugin_version_id,
          references(:plugin_versions, type: :binary_id, on_delete: :nilify_all)

      add :position, :integer, default: 0
      add :enabled, :boolean, default: true
      add :config_override, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:service_plugins, [:service_id, :plugin_id])
    create index(:service_plugins, [:service_id])
  end
end
