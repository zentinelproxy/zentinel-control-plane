defmodule ZentinelCpWeb.GraphQL.Types.Subscription do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias ZentinelCp.{Access, Rollouts}

  object :subscription_fields do
    field :rollout_progress, :rollout do
      arg(:rollout_id, non_null(:id))

      config(fn args, %{context: context} ->
        rollout = Rollouts.get_rollout(args.rollout_id)
        authorize_topic(context, rollout && rollout.project_id, "rollouts:read", args.rollout_id)
      end)
    end

    field :node_status, :zentinel_node do
      arg(:project_id, non_null(:id))

      config(fn args, %{context: context} ->
        authorize_topic(context, args.project_id, "nodes:read", args.project_id)
      end)
    end

    field :alert_state, :alert_state do
      arg(:project_id, non_null(:id))

      config(fn args, %{context: context} ->
        authorize_topic(context, args.project_id, "services:read", args.project_id)
      end)
    end
  end

  defp authorize_topic(context, project_id, scope, topic) do
    if Access.api_key_allowed?(context[:current_api_key], project_id, scope) do
      {:ok, topic: topic}
    else
      {:error, "Not found"}
    end
  end
end
