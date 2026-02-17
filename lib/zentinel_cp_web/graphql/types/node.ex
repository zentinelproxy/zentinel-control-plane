defmodule ZentinelCpWeb.GraphQL.Types.Node do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias ZentinelCpWeb.GraphQL.Resolvers

  object :zentinel_node do
    field :id, non_null(:id)
    field :hostname, :string
    field :status, non_null(:string)
    field :labels, :json

    field :last_heartbeat_at, :datetime do
      resolve(fn node, _, _ -> {:ok, node.last_seen_at} end)
    end
  end

  object :node_queries do
    field :nodes, list_of(:zentinel_node) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Nodes.list/3)
    end
  end
end
