defmodule SentinelCpWeb.GraphQL.Types.Policy do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SentinelCpWeb.GraphQL.Resolvers

  object :policy do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :policy_type, non_null(:string)
    field :expression, :string
    field :enforcement, non_null(:string)
    field :enabled, non_null(:boolean)
  end

  object :policy_queries do
    field :policies, list_of(:policy) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Policies.list/3)
    end
  end
end
