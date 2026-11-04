defmodule ZentinelCpWeb.GraphQL.Resolvers.Projects do
  @moduledoc false
  alias ZentinelCp.{Access, Projects}

  def get(_parent, %{id: id}, %{context: context}) do
    id |> Projects.get_project() |> authorize(context)
  end

  def get(_parent, %{slug: slug}, %{context: context}) do
    slug |> Projects.get_project_by_slug() |> authorize(context)
  end

  def get(_parent, _args, _resolution) do
    {:error, "Either id or slug is required"}
  end

  def list(_parent, args, %{context: %{current_api_key: api_key}}) do
    opts = if args[:org_id], do: [org_id: args[:org_id]], else: []
    {:ok, Access.visible_projects(api_key, opts)}
  end

  defp authorize(project, %{current_api_key: api_key}) do
    if Access.api_key_allowed?(api_key, project, "services:read"),
      do: {:ok, project},
      else: {:error, "Project not found"}
  end
end
