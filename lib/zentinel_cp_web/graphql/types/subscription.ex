defmodule ZentinelCpWeb.GraphQL.Types.Subscription do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :subscription_fields do
    field :rollout_progress, :rollout do
      arg(:rollout_id, non_null(:id))
      config(fn args, _ -> {:ok, topic: args.rollout_id} end)
    end

    field :node_status, :zentinel_node do
      arg(:project_id, non_null(:id))
      config(fn args, _ -> {:ok, topic: args.project_id} end)
    end

    field :alert_state, :alert_state do
      arg(:project_id, non_null(:id))
      config(fn args, _ -> {:ok, topic: args.project_id} end)
    end
  end
end
