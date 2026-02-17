defmodule ZentinelCp.Repo.Migrations.CreateProjectsTable do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:slug])

    # Add foreign key constraint to api_keys now that projects exists
    # Note: SQLite doesn't support adding FK constraints after table creation,
    # so we just create an index for now. The FK is enforced at app level.
  end
end
