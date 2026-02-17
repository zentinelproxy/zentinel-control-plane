defmodule ZentinelCp.Policies do
  @moduledoc """
  The Policies context for policy-as-code governance.

  Provides CRUD for policies, expression evaluation against action contexts,
  and violation recording. Integrates at service/rollout/access boundaries.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Policies.{Policy, Violation, Evaluator}

  require Logger

  ## CRUD

  @doc "Creates a new policy."
  def create_policy(attrs) do
    %Policy{}
    |> Policy.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing policy."
  def update_policy(policy, attrs) do
    policy
    |> Policy.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets a policy by ID."
  def get_policy(id), do: Repo.get(Policy, id)

  @doc "Lists all policies for a project."
  def list_policies(project_id) do
    from(p in Policy, where: p.project_id == ^project_id, order_by: [asc: p.name])
    |> Repo.all()
  end

  @doc "Lists policies by type for a project."
  def list_policies_by_type(project_id, policy_type) do
    from(p in Policy,
      where: p.project_id == ^project_id and p.policy_type == ^policy_type and p.enabled == true,
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  @doc "Deletes a policy."
  def delete_policy(policy), do: Repo.delete(policy)

  ## Evaluation

  @doc """
  Evaluates all enabled policies of a given type against a context.

  Returns `{:ok, violations}` where violations is a list of
  `{policy, message}` tuples. In enforce mode, a non-empty violations
  list means the action should be blocked.

  ## Options
  - `:dry_run` — override all policies to dry_run mode
  """
  def evaluate(project_id, policy_type, context, opts \\ []) do
    policies = list_policies_by_type(project_id, policy_type)
    dry_run = Keyword.get(opts, :dry_run, false)

    violations =
      policies
      |> Enum.reduce([], fn policy, acc ->
        case Evaluator.evaluate(policy.expression, context) do
          {:ok, true} ->
            acc

          {:ok, false} ->
            violation = record_violation(policy, context, dry_run)
            [{policy, violation} | acc]

          {:error, reason} ->
            Logger.warning("Policy #{policy.name} evaluation error: #{reason}")
            acc
        end
      end)
      |> Enum.reverse()

    enforced =
      Enum.filter(violations, fn {policy, _} ->
        not dry_run and policy.enforcement == "enforce"
      end)

    if enforced == [] do
      {:ok, violations}
    else
      messages =
        Enum.map(enforced, fn {policy, _} ->
          "Policy '#{policy.name}' violated: #{policy.expression}"
        end)

      {:error, {:policy_violation, messages}}
    end
  end

  @doc """
  Evaluates policies in dry-run mode (never blocks).
  """
  def evaluate_dry_run(project_id, policy_type, context) do
    evaluate(project_id, policy_type, context, dry_run: true)
  end

  ## Violations

  @doc "Lists recent violations for a project."
  def list_violations(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(v in Violation,
      where: v.project_id == ^project_id,
      order_by: [desc: v.inserted_at],
      limit: ^limit,
      preload: [:policy]
    )
    |> Repo.all()
  end

  @doc "Counts violations for a project."
  def violation_count(project_id) do
    from(v in Violation, where: v.project_id == ^project_id)
    |> Repo.aggregate(:count)
  end

  ## Private

  defp record_violation(policy, context, dry_run) do
    resource_type =
      Map.get(context, "resource_type") || Map.get(context, :resource_type, "unknown")

    resource_id = Map.get(context, "resource_id") || Map.get(context, :resource_id)
    action = Map.get(context, "action") || Map.get(context, :action, "unknown")

    {:ok, violation} =
      %Violation{}
      |> Violation.changeset(%{
        policy_id: policy.id,
        project_id: policy.project_id,
        resource_type: to_string(resource_type),
        resource_id: resource_id,
        action: to_string(action),
        message: "Policy '#{policy.name}' violated: #{policy.expression}",
        context: stringify_context(context),
        dry_run: dry_run || policy.enforcement == "dry_run"
      })
      |> Repo.insert()

    violation
  end

  defp stringify_context(context) when is_map(context) do
    Map.new(context, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_atom(v), do: to_string(v)
  defp stringify_value(v) when is_binary(v), do: v
  defp stringify_value(v) when is_number(v), do: v
  defp stringify_value(v) when is_boolean(v), do: v
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v) when is_map(v), do: stringify_context(v)
  defp stringify_value(v), do: inspect(v)
end
