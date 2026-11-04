defmodule ZentinelCp.Repo.Migrations.RestoreGlobalProjectSlugUnique do
  use Ecto.Migration

  # Most lookups, including node registration and every API route, find a project
  # by slug alone, so a duplicate slug in another org would break them. If this
  # fails on duplicate slugs, rename the projects involved and migrate again.
  def change do
    drop_if_exists unique_index(:projects, [:org_id, :slug])
    create unique_index(:projects, [:slug])
  end
end
