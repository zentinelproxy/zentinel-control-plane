defmodule ZentinelCp.Waf.WafPolicyRuleOverride do
  @moduledoc """
  Schema for per-rule action overrides within a WAF policy.

  Allows overriding the default action for specific rules within a policy,
  e.g., setting a specific rule to "log" instead of "block".
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(block log disable)

  schema "waf_policy_rule_overrides" do
    field :action, :string
    field :note, :string

    belongs_to :waf_policy, ZentinelCp.Waf.WafPolicy
    belongs_to :waf_rule, ZentinelCp.Waf.WafRule

    timestamps(type: :utc_datetime)
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:action, :note, :waf_policy_id, :waf_rule_id])
    |> validate_required([:action, :waf_policy_id, :waf_rule_id])
    |> validate_inclusion(:action, @actions)
    |> unique_constraint([:waf_policy_id, :waf_rule_id],
      error_key: :waf_rule_id,
      message: "override already exists for this rule"
    )
    |> foreign_key_constraint(:waf_policy_id)
    |> foreign_key_constraint(:waf_rule_id)
  end
end
