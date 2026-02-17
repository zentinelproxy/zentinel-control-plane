defmodule ZentinelCpWeb.GraphQL.Resolvers.Policies do
  @moduledoc false
  alias ZentinelCp.Policies

  def list(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Policies.list_policies(project_id)}
  end
end
