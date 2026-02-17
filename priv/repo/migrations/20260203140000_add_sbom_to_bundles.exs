defmodule ZentinelCp.Repo.Migrations.AddSbomToBundles do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :sbom, :map
      add :sbom_format, :string
    end
  end
end
