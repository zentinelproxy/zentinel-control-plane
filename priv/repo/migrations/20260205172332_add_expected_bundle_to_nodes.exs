defmodule ZentinelCp.Repo.Migrations.AddExpectedBundleToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :expected_bundle_id, :binary_id
    end

    create index(:nodes, [:expected_bundle_id])
  end
end
