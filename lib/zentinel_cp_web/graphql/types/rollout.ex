defmodule ZentinelCpWeb.GraphQL.Types.Rollout do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias ZentinelCpWeb.GraphQL.Resolvers

  object :rollout do
    field :id, non_null(:id)
    field :state, non_null(:string)
    field :strategy, non_null(:string)
    field :deployment_slot, :string
    field :blue_green_config, :json
    field :traffic_step_index, :integer
    field :target_selector, :json
    field :inserted_at, non_null(:datetime)

    field :progress, :json do
      resolve(&Resolvers.Rollouts.resolve_progress/3)
    end

    field :steps, list_of(:rollout_step) do
      resolve(&Resolvers.Rollouts.resolve_steps/3)
    end
  end

  object :rollout_step do
    field :id, non_null(:id)
    field :step_index, non_null(:integer)
    field :state, non_null(:string)
    field :node_ids, list_of(:string)
    field :deployment_slot, :string
    field :traffic_weight, :integer
    field :started_at, :datetime
    field :completed_at, :datetime
  end

  input_object :create_rollout_input do
    field :project_id, non_null(:id)
    field :bundle_id, non_null(:id)
    field :strategy, :string
    field :target_selector, :json
    field :blue_green_config, :json
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

    field :swap_blue_green_slot, :rollout do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Rollouts.swap_slot/3)
    end

    field :advance_blue_green_traffic, :rollout do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Rollouts.advance_traffic/3)
    end
  end
end
