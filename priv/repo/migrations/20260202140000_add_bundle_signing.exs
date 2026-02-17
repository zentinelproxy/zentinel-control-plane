defmodule ZentinelCp.Repo.Migrations.AddBundleSigning do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :signature, :binary
      add :signing_key_id, :string
    end
  end
end
