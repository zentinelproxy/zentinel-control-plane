defmodule ZentinelCp.Waf do
  @moduledoc """
  Context for WAF rule catalog, policies, and per-rule overrides.

  Provides CRUD operations and the key `get_effective_rules/1` function
  that merges policy settings with per-rule overrides.
  """

  alias ZentinelCp.Repo

  alias ZentinelCp.Waf.{
    BuiltInRules,
    WafPolicy,
    WafPolicyRuleOverride,
    WafRule
  }

  import Ecto.Query

  ## Rules

  @doc """
  Lists all WAF rules, ordered by category then rule_id.
  Ensures built-in rules exist first.
  """
  def list_rules(opts \\ []) do
    BuiltInRules.ensure_built_ins!()

    query = from(r in WafRule, order_by: [asc: r.category, asc: r.rule_id])

    query =
      case Keyword.get(opts, :category) do
        nil -> query
        cat -> where(query, [r], r.category == ^cat)
      end

    query =
      case Keyword.get(opts, :severity) do
        nil -> query
        sev -> where(query, [r], r.severity == ^sev)
      end

    query =
      case Keyword.get(opts, :search) do
        nil ->
          query

        term ->
          pattern = "%#{term}%"
          where(query, [r], like(r.name, ^pattern) or like(r.rule_id, ^pattern))
      end

    Repo.all(query)
  end

  @doc "Gets a single WAF rule by ID."
  def get_rule(id), do: Repo.get(WafRule, id)

  @doc "Gets a single WAF rule by ID, raises if not found."
  def get_rule!(id), do: Repo.get!(WafRule, id)

  @doc "Gets a WAF rule by its rule_id string (e.g. \"CRS-942100\")."
  def get_rule_by_rule_id(rule_id) do
    Repo.get_by(WafRule, rule_id: rule_id)
  end

  ## Policies

  @doc "Lists WAF policies for a project, ordered by name."
  def list_policies(project_id) do
    from(p in WafPolicy,
      where: p.project_id == ^project_id,
      order_by: [asc: p.name],
      preload: [:services]
    )
    |> Repo.all()
  end

  @doc "Gets a single WAF policy by ID."
  def get_policy(id), do: Repo.get(WafPolicy, id)

  @doc "Gets a single WAF policy by ID, raises if not found."
  def get_policy!(id), do: Repo.get!(WafPolicy, id)

  @doc "Gets a WAF policy with rule overrides preloaded."
  def get_policy_with_overrides!(id) do
    WafPolicy
    |> Repo.get!(id)
    |> Repo.preload(rule_overrides: :waf_rule)
  end

  @doc "Creates a WAF policy."
  def create_policy(attrs) do
    %WafPolicy{}
    |> WafPolicy.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a WAF policy."
  def update_policy(%WafPolicy{} = policy, attrs) do
    policy
    |> WafPolicy.update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a WAF policy."
  def delete_policy(%WafPolicy{} = policy) do
    Repo.delete(policy)
  end

  @doc "Returns a changeset for tracking WAF policy changes in forms."
  def change_policy(%WafPolicy{} = policy, attrs \\ %{}) do
    WafPolicy.update_changeset(policy, attrs)
  end

  ## Rule Overrides

  @doc "Lists rule overrides for a policy."
  def list_overrides(policy_id) do
    from(o in WafPolicyRuleOverride,
      where: o.waf_policy_id == ^policy_id,
      preload: [:waf_rule],
      order_by: [asc: :inserted_at]
    )
    |> Repo.all()
  end

  @doc "Creates or updates a rule override for a policy."
  def upsert_override(attrs) do
    case Repo.get_by(WafPolicyRuleOverride,
           waf_policy_id: attrs[:waf_policy_id] || attrs["waf_policy_id"],
           waf_rule_id: attrs[:waf_rule_id] || attrs["waf_rule_id"]
         ) do
      nil ->
        %WafPolicyRuleOverride{}
        |> WafPolicyRuleOverride.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> WafPolicyRuleOverride.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Deletes a rule override (struct or ID)."
  def delete_override(%WafPolicyRuleOverride{} = override) do
    Repo.delete(override)
  end

  def delete_override(id) do
    case Repo.get(WafPolicyRuleOverride, id) do
      nil -> {:error, :not_found}
      override -> Repo.delete(override)
    end
  end

  ## Effective Rules

  @doc """
  Computes the effective rules for a WAF policy.

  Merges policy-level settings (enabled categories, mode, sensitivity)
  with per-rule overrides to produce a list of `{rule, effective_action}` tuples.

  Rules in disabled categories are excluded. Per-rule overrides take
  precedence over the policy's default action.
  """
  def get_effective_rules(%WafPolicy{} = policy) do
    BuiltInRules.ensure_built_ins!()
    policy = Repo.preload(policy, rule_overrides: :waf_rule)

    # Build override lookup: rule_id -> override action
    override_map =
      policy.rule_overrides
      |> Enum.into(%{}, fn o -> {o.waf_rule_id, o.action} end)

    # Get all rules in enabled categories
    enabled_cats = policy.enabled_categories || []

    rules =
      if enabled_cats == [] do
        []
      else
        from(r in WafRule,
          where: r.category in ^enabled_cats,
          order_by: [asc: r.category, asc: r.rule_id]
        )
        |> Repo.all()
      end

    # Merge: override action > policy default_action > rule default_action
    Enum.reduce(rules, [], fn rule, acc ->
      effective_action =
        case Map.get(override_map, rule.id) do
          "disable" -> nil
          action when not is_nil(action) -> action
          nil -> policy.default_action || rule.default_action
        end

      if effective_action do
        [{rule, effective_action} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  def get_effective_rules(policy_id) when is_binary(policy_id) do
    case get_policy(policy_id) do
      nil -> []
      policy -> get_effective_rules(policy)
    end
  end
end
