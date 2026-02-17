defmodule ZentinelCpWeb.GraphQL.Resolvers.Nodes do
  @moduledoc false
  alias ZentinelCp.Nodes

  def list(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Nodes.list_nodes(project_id)}
  end

  def list_for_project(project, _args, _resolution) do
    {:ok, Nodes.list_nodes(project.id)}
  end
end
