defmodule SentinelCpWeb.GraphQL.Resolvers.Projects do
  @moduledoc false
  alias SentinelCp.Projects

  def get(_parent, %{id: id}, _resolution) do
    case Projects.get_project(id) do
      nil -> {:error, "Project not found"}
      project -> {:ok, project}
    end
  end

  def get(_parent, %{slug: slug}, _resolution) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, "Project not found"}
      project -> {:ok, project}
    end
  end

  def get(_parent, _args, _resolution) do
    {:error, "Either id or slug is required"}
  end

  def list(_parent, args, _resolution) do
    opts = if args[:org_id], do: [org_id: args[:org_id]], else: []
    {:ok, Projects.list_projects(opts)}
  end
end
