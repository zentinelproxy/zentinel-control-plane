defmodule SentinelCpWeb.GraphQL.Types.Project do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SentinelCpWeb.GraphQL.Resolvers

  object :project do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :slug, non_null(:string)
    field :description, :string
    field :settings, :json
    field :inserted_at, non_null(:datetime)

    field :services, list_of(:service) do
      resolve(&Resolvers.Services.list_for_project/3)
    end

    field :nodes, list_of(:sentinel_node) do
      resolve(&Resolvers.Nodes.list_for_project/3)
    end

    field :bundles, list_of(:bundle) do
      arg(:limit, :integer, default_value: 50)
      resolve(&Resolvers.Bundles.list_for_project/3)
    end

    field :rollouts, list_of(:rollout) do
      resolve(&Resolvers.Rollouts.list_for_project/3)
    end
  end

  object :project_queries do
    field :project, :project do
      arg(:id, :id)
      arg(:slug, :string)
      resolve(&Resolvers.Projects.get/3)
    end

    field :projects, list_of(:project) do
      arg(:org_id, :id)
      resolve(&Resolvers.Projects.list/3)
    end
  end
end
