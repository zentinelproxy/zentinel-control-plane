defmodule ZentinelCp.Repo.Migrations.AddActiveBundleToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :active_bundle_id, :binary_id
      add :staged_bundle_id, :binary_id
    end
  end
end
