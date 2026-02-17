defmodule ZentinelCpWeb.GraphQL.Types.Service do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias ZentinelCpWeb.GraphQL.Resolvers

  object :service do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :slug, non_null(:string)
    field :route_path, :string
    field :upstream_url, :string
    field :enabled, non_null(:boolean)
    field :position, non_null(:integer)
  end

  object :service_queries do
    field :services, list_of(:service) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Services.list/3)
    end
  end
end
