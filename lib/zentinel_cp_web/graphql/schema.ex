defmodule ZentinelCpWeb.GraphQL.Schema do
  @moduledoc false
  use Absinthe.Schema

  import_types(ZentinelCpWeb.GraphQL.Types.CustomScalars)
  import_types(ZentinelCpWeb.GraphQL.Types.Project)
  import_types(ZentinelCpWeb.GraphQL.Types.Service)
  import_types(ZentinelCpWeb.GraphQL.Types.Node)
  import_types(ZentinelCpWeb.GraphQL.Types.Bundle)
  import_types(ZentinelCpWeb.GraphQL.Types.Rollout)
  import_types(ZentinelCpWeb.GraphQL.Types.Observability)
  import_types(ZentinelCpWeb.GraphQL.Types.Policy)
  import_types(ZentinelCpWeb.GraphQL.Types.Subscription)

  query do
    import_fields(:project_queries)
    import_fields(:service_queries)
    import_fields(:node_queries)
    import_fields(:bundle_queries)
    import_fields(:rollout_queries)
    import_fields(:observability_queries)
    import_fields(:policy_queries)
  end

  mutation do
    import_fields(:bundle_mutations)
    import_fields(:rollout_mutations)
  end

  subscription do
    import_fields(:subscription_fields)
  end

  def middleware(middleware, _field, %Absinthe.Type.Object{identifier: identifier})
      when identifier in [:query, :mutation] do
    [ZentinelCpWeb.GraphQL.Middleware.AuthScope | middleware]
  end

  def middleware(middleware, _field, _object), do: middleware
end
