defmodule ZentinelCp.Repo.Migrations.AddParentBundleId do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :parent_bundle_id, references(:bundles, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:bundles, [:parent_bundle_id])
  end
end
