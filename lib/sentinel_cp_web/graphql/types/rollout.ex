defmodule SentinelCpWeb.GraphQL.Types.Rollout do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SentinelCpWeb.GraphQL.Resolvers

  object :rollout do
    field :id, non_null(:id)
    field :state, non_null(:string)
    field :strategy, non_null(:string)
    field :target_selector, :json
    field :inserted_at, non_null(:datetime)

    field :progress, :json do
      resolve(&Resolvers.Rollouts.resolve_progress/3)
    end
  end

  input_object :create_rollout_input do
    field :project_id, non_null(:id)
    field :bundle_id, non_null(:id)
    field :strategy, :string
    field :target_selector, :json
  end

  object :rollout_queries do
    field :rollouts, list_of(:rollout) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Rollouts.list/3)
    end
  end

  object :rollout_mutations do
    field :create_rollout, :rollout do
      arg(:input, non_null(:create_rollout_input))
      resolve(&Resolvers.Rollouts.create/3)
    end

    field :pause_rollout, :rollout do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Rollouts.pause/3)
    end

    field :resume_rollout, :rollout do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Rollouts.resume/3)
    end
  end
end
