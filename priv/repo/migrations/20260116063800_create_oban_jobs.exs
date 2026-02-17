defmodule ZentinelCp.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  def up do
    if Application.get_env(:zentinel_cp, :ecto_adapter) == Ecto.Adapters.Postgres do
      # PostgreSQL Oban tables are handled by the earlier migration
      :ok
    else
      Oban.Migrations.SQLite.up(version: 1)
    end
  end

  def down do
    if Application.get_env(:zentinel_cp, :ecto_adapter) == Ecto.Adapters.Postgres do
      :ok
    else
      Oban.Migrations.SQLite.down(version: 1)
    end
  end
end
