defmodule ZentinelCp.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.

  Usage:

      bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
      bin/zentinel_cp eval "ZentinelCp.Release.seed()"
  """

  @app :zentinel_cp

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")

          if File.exists?(seed_file) do
            Code.eval_file(seed_file)
          end
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
