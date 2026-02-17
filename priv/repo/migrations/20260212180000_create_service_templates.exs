defmodule ZentinelCp.Repo.Migrations.CreateServiceTemplates do
  use Ecto.Migration

  def change do
    create table(:service_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :category, :string, null: false
      add :template_data, :map, default: %{}
      add :version, :integer, default: 1
      add :is_builtin, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:service_templates, [:project_id])
    create unique_index(:service_templates, [:project_id, :slug], where: "project_id IS NOT NULL")

    create unique_index(:service_templates, [:slug],
             where: "is_builtin = true",
             name: :service_templates_builtin_slug_index
           )
  end
end
