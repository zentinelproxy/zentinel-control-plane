defmodule ZentinelCp.Repo.Migrations.CreateOpenapiSpecs do
  use Ecto.Migration

  def change do
    create table(:openapi_specs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :file_name, :string, null: false
      add :openapi_version, :string
      add :spec_version, :string
      add :spec_data, :map, null: false
      add :checksum, :string, null: false
      add :paths_count, :integer, default: 0
      add :status, :string, default: "active", null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:openapi_specs, [:project_id])
    create index(:openapi_specs, [:project_id, :status])

    alter table(:services) do
      add :openapi_spec_id,
          references(:openapi_specs, type: :binary_id, on_delete: :nilify_all)

      add :openapi_path, :string
    end

    create index(:services, [:openapi_spec_id])
  end
end
