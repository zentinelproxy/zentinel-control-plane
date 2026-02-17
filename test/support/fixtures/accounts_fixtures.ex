defmodule ZentinelCp.AccountsFixtures do
  @moduledoc """
  Test helpers for creating Accounts entities.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world!123"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      role: "operator"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> ZentinelCp.Accounts.register_user()

    user
  end

  def admin_fixture(attrs \\ %{}) do
    user_fixture(Map.put(attrs, :role, "admin"))
  end

  def api_key_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, api_key} =
      ZentinelCp.Accounts.create_api_key(%{
        name: attrs[:name] || "test-key-#{System.unique_integer([:positive])}",
        user_id: user.id,
        project_id: project.id,
        scopes: attrs[:scopes] || [],
        expires_at: attrs[:expires_at]
      })

    api_key
  end
end
