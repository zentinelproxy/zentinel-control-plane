defmodule SentinelCpWeb.GraphQL.Schema do
  @moduledoc false
  use Absinthe.Schema

  import_types(SentinelCpWeb.GraphQL.Types.CustomScalars)
  import_types(SentinelCpWeb.GraphQL.Types.Project)
  import_types(SentinelCpWeb.GraphQL.Types.Service)
  import_types(SentinelCpWeb.GraphQL.Types.Node)
  import_types(SentinelCpWeb.GraphQL.Types.Bundle)
  import_types(SentinelCpWeb.GraphQL.Types.Rollout)
  import_types(SentinelCpWeb.GraphQL.Types.Observability)
  import_types(SentinelCpWeb.GraphQL.Types.Policy)

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

  def middleware(middleware, _field, %Absinthe.Type.Object{identifier: identifier})
      when identifier in [:query, :mutation] do
    [SentinelCpWeb.GraphQL.Middleware.AuthScope | middleware]
  end

  def middleware(middleware, _field, _object), do: middleware
end
