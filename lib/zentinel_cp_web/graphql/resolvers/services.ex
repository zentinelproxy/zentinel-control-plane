defmodule ZentinelCpWeb.GraphQL.Resolvers.Services do
  @moduledoc false
  alias ZentinelCp.Services

  def list(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Services.list_services(project_id)}
  end

  def list_for_project(project, _args, _resolution) do
    {:ok, Services.list_services(project.id)}
  end
end
