defmodule ZentinelCp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    # Oban.Engines.Lite uses SQLite-specific tables
    # Oban.Engines.Basic uses PostgreSQL tables
    # The migration needs to handle both depending on the adapter
    if Application.get_env(:zentinel_cp, :ecto_adapter) == Ecto.Adapters.Postgres do
      Oban.Migration.up(version: 12)
    else
      # For SQLite, Oban.Engines.Lite creates its own tables automatically
      :ok
    end
  end

  def down do
    if Application.get_env(:zentinel_cp, :ecto_adapter) == Ecto.Adapters.Postgres do
      Oban.Migration.down(version: 1)
    else
      :ok
    end
  end
end
