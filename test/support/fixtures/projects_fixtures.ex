defmodule ZentinelCp.ProjectsFixtures do
  @moduledoc """
  Test helpers for creating Projects entities.
  """

  def unique_project_name, do: "project-#{System.unique_integer([:positive])}"

  def valid_project_attributes(attrs \\ %{}) do
    org = attrs[:org] || ZentinelCp.OrgsFixtures.org_fixture()

    base = %{
      name: unique_project_name(),
      description: "A test project",
      org_id: org.id
    }

    base =
      if Map.has_key?(attrs, :settings) do
        Map.put(base, :settings, attrs[:settings])
      else
        base
      end

    Enum.into(Map.drop(attrs, [:org, :settings]), base)
  end

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> valid_project_attributes()
      |> ZentinelCp.Projects.create_project()

    project
  end
end
