defmodule ZentinelCp.ServicesFixtures do
  @moduledoc """
  Test helpers for creating Services entities.
  """

  def unique_service_name, do: "service-#{System.unique_integer([:positive])}"

  def valid_service_attributes(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    Enum.into(Map.drop(attrs, [:project]), %{
      name: unique_service_name(),
      description: "A test service",
      route_path: "/api/*",
      upstream_url: "http://localhost:3000",
      project_id: project.id
    })
  end

  def service_fixture(attrs \\ %{}) do
    {:ok, service} =
      attrs
      |> valid_service_attributes()
      |> ZentinelCp.Services.create_service()

    service
  end

  def redirect_service_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, service} =
      ZentinelCp.Services.create_service(%{
        name: attrs[:name] || unique_service_name(),
        description: attrs[:description] || "A redirect service",
        route_path: attrs[:route_path] || "/old/*",
        redirect_url: attrs[:redirect_url] || "https://new.example.com",
        project_id: project.id
      })

    service
  end

  def static_service_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, service} =
      ZentinelCp.Services.create_service(%{
        name: attrs[:name] || unique_service_name(),
        description: attrs[:description] || "A static response service",
        route_path: attrs[:route_path] || "/health",
        respond_status: attrs[:respond_status] || 200,
        respond_body: attrs[:respond_body] || "OK",
        project_id: project.id
      })

    service
  end
end
