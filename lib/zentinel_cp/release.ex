defmodule ZentinelCp.Release do
  @moduledoc """
  Release tasks for running migrations and bootstrapping in production.

  Usage:

      bin/zentinel_cp eval "ZentinelCp.Release.migrate()"
      bin/zentinel_cp eval "ZentinelCp.Release.bootstrap_admin()"
      bin/zentinel_cp eval "ZentinelCp.Release.reencrypt_secrets()"
  """

  @app :zentinel_cp

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Creates the first admin and default org from `ADMIN_EMAIL` and `ADMIN_PASSWORD`.

  Does nothing once any user exists, so it is safe to run on every boot, and it
  cannot recreate an admin that has been removed. No default credentials exist:
  without those variables no admin is created.
  """
  def bootstrap_admin do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          create_first_admin(System.get_env("ADMIN_EMAIL"), System.get_env("ADMIN_PASSWORD"))
        end)
    end
  end

  @doc false
  def create_first_admin(email, password) do
    cond do
      ZentinelCp.Repo.aggregate(ZentinelCp.Accounts.User, :count) > 0 ->
        :already_bootstrapped

      blank?(email) or blank?(password) ->
        IO.puts("No users exist. Set ADMIN_EMAIL and ADMIN_PASSWORD to create the first admin.")
        :no_credentials

      true ->
        with {:ok, user} <-
               ZentinelCp.Accounts.register_user(%{
                 email: email,
                 password: password,
                 role: "admin"
               }),
             {:ok, _org} <- ZentinelCp.Orgs.create_org_with_owner(%{name: "Default"}, user) do
          IO.puts("Created admin user: #{user.email}")
          :ok
        else
          {:error, reason} -> raise "Could not create the first admin: #{inspect(reason)}"
        end
    end
  end

  defp blank?(value), do: value in [nil, ""]

  @doc """
  Re-encrypts stored secrets with the current key. Run after setting
  `ENCRYPTION_KEY` on an existing install, and after rotating it.
  """
  def reencrypt_secrets do
    load_app()

    for repo <- repos() do
      {:ok, counts, _} =
        Ecto.Migrator.with_repo(repo, fn _repo -> ZentinelCp.SecretRotation.run() end)

      Enum.each(counts, fn {schema, field, count} ->
        IO.puts("Re-encrypted #{count} #{inspect(schema)}.#{field}")
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
