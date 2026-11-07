defmodule ZentinelCp.Repo.Migrations.UpgradeObanJobsToV14 do
  use Ecto.Migration

  # Oban's SQLite schema has a single version, which is already applied.
  def up do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      Oban.Migrations.up(version: 14)
    end
  end

  def down do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      Oban.Migrations.down(version: 12)
    end
  end
end
