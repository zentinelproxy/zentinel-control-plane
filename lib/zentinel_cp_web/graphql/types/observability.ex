defmodule ZentinelCpWeb.GraphQL.Types.Observability do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias ZentinelCpWeb.GraphQL.Resolvers

  object :alert_rule do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :rule_type, non_null(:string)
    field :condition, :json
    field :severity, non_null(:string)
    field :enabled, non_null(:boolean)
  end

  object :slo do
    field :id, non_null(:id)
    field :name, non_null(:string)
    field :sli_type, non_null(:string)
    field :target, non_null(:float)
    field :burn_rate, :float
    field :error_budget_remaining, :float
  end

  object :alert_state do
    field :id, non_null(:id)
    field :state, non_null(:string)
    field :value, :float
    field :started_at, :datetime
    field :firing_at, :datetime
    field :resolved_at, :datetime
  end

  object :observability_queries do
    field :alert_rules, list_of(:alert_rule) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Observability.list_alert_rules/3)
    end

    field :slos, list_of(:slo) do
      arg(:project_id, non_null(:id))
      resolve(&Resolvers.Observability.list_slos/3)
    end
  end
end
