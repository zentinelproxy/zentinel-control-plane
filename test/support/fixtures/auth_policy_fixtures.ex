defmodule ZentinelCp.AuthPolicyFixtures do
  @moduledoc """
  Test helpers for creating AuthPolicy entities.
  """

  def unique_policy_name, do: "policy-#{System.unique_integer([:positive])}"

  def auth_policy_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, policy} =
      ZentinelCp.Services.create_auth_policy(%{
        name: attrs[:name] || unique_policy_name(),
        description: attrs[:description] || "A test auth policy",
        auth_type: attrs[:auth_type] || "jwt",
        config: attrs[:config] || %{"issuer" => "https://auth.example.com"},
        enabled: Map.get(attrs, :enabled, true),
        project_id: project.id
      })

    policy
  end
end
