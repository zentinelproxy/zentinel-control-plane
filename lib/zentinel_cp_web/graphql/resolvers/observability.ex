defmodule ZentinelCpWeb.GraphQL.Resolvers.Observability do
  @moduledoc false
  alias ZentinelCp.Observability

  def list_alert_rules(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Observability.list_alert_rules(project_id)}
  end

  def list_slos(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Observability.list_slos(project_id)}
  end
end
