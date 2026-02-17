defmodule ZentinelCp.ServiceTemplateFixtures do
  @moduledoc """
  Test helpers for creating ServiceTemplate entities.
  """

  def unique_template_name, do: "template-#{System.unique_integer([:positive])}"

  def template_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, template} =
      ZentinelCp.Services.create_template(%{
        name: attrs[:name] || unique_template_name(),
        description: attrs[:description] || "A test template",
        category: attrs[:category] || "api",
        template_data:
          attrs[:template_data] ||
            %{
              "route_path" => "/api/*",
              "upstream_url" => "http://backend:8080"
            },
        project_id: project.id
      })

    template
  end
end
