defmodule ZentinelCp.MiddlewareFixtures do
  @moduledoc """
  Test helpers for creating Middleware and ServiceMiddleware entities.
  """

  def unique_middleware_name, do: "middleware-#{System.unique_integer([:positive])}"

  def middleware_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, middleware} =
      ZentinelCp.Services.create_middleware(%{
        name: attrs[:name] || unique_middleware_name(),
        description: attrs[:description] || "A test middleware",
        middleware_type: attrs[:middleware_type] || "cors",
        config: attrs[:config] || %{"allow_origins" => "*", "allow_methods" => "GET,POST"},
        enabled: Map.get(attrs, :enabled, true),
        project_id: project.id
      })

    middleware
  end

  def service_middleware_fixture(attrs \\ %{}) do
    service = attrs[:service] || ZentinelCp.ServicesFixtures.service_fixture()
    middleware = attrs[:middleware] || middleware_fixture(%{project: attrs[:project]})

    {:ok, sm} =
      ZentinelCp.Services.attach_middleware(%{
        service_id: service.id,
        middleware_id: middleware.id,
        position: attrs[:position] || 0,
        enabled: Map.get(attrs, :enabled, true),
        config_override: attrs[:config_override] || %{}
      })

    sm
  end
end
