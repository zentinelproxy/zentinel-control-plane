defmodule ZentinelCp.UpstreamGroupFixtures do
  @moduledoc """
  Test helpers for creating UpstreamGroup entities.
  """

  def unique_group_name, do: "group-#{System.unique_integer([:positive])}"

  def upstream_group_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, group} =
      ZentinelCp.Services.create_upstream_group(%{
        name: attrs[:name] || unique_group_name(),
        description: attrs[:description] || "A test upstream group",
        algorithm: attrs[:algorithm] || "round_robin",
        project_id: project.id
      })

    group
  end

  def upstream_target_fixture(attrs \\ %{}) do
    group = attrs[:group] || upstream_group_fixture()

    {:ok, target} =
      ZentinelCp.Services.add_upstream_target(%{
        upstream_group_id: group.id,
        host: attrs[:host] || "api.internal",
        port: attrs[:port] || 8080,
        weight: attrs[:weight] || 100
      })

    target
  end
end
