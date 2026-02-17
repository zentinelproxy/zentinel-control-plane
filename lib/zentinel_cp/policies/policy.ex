defmodule ZentinelCp.Policies.Policy do
  @moduledoc """
  Schema for policy-as-code rules.

  ## Policy Types
  - `deployment` — evaluated at rollout creation/promotion
  - `configuration` — evaluated at service creation/update
  - `access` — evaluated at authorization time

  ## Enforcement Modes
  - `enforce` — block the action on violation
  - `dry_run` — log violation but allow the action

  ## Expression Syntax
  Policies use a simple expression language:
  - `day_of_week != "friday"` — time-based checks
  - `strategy in ["rolling", "canary"]` — inclusion checks
  - `approvals >= 2` — numeric comparisons
  - `has_rate_limit == true` — boolean checks
  - Expressions use `==`, `!=`, `>`, `<`, `>=`, `<=`, `in`, `not_in`, `contains`
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @policy_types ~w(deployment configuration access)
  @enforcement_modes ~w(enforce dry_run)
  @severities ~w(critical warning info)

  schema "policies" do
    field :name, :string
    field :description, :string
    field :policy_type, :string
    field :expression, :string
    field :enforcement, :string, default: "enforce"
    field :enabled, :boolean, default: true
    field :severity, :string, default: "warning"
    field :version, :integer, default: 1
    field :labels, :map, default: %{}

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :project_id,
      :name,
      :description,
      :policy_type,
      :expression,
      :enforcement,
      :enabled,
      :severity,
      :version,
      :labels
    ])
    |> validate_required([:project_id, :name, :policy_type, :expression])
    |> validate_inclusion(:policy_type, @policy_types)
    |> validate_inclusion(:enforcement, @enforcement_modes)
    |> validate_inclusion(:severity, @severities)
    |> validate_expression()
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  defp validate_expression(changeset) do
    expression = get_field(changeset, :expression)

    if expression && not valid_expression?(expression) do
      add_error(changeset, :expression, "contains invalid syntax")
    else
      changeset
    end
  end

  defp valid_expression?(expr) when is_binary(expr) do
    # Basic validation: must contain an operator
    String.contains?(expr, ["==", "!=", ">", "<", ">=", "<=", " in ", " not_in ", "contains"])
  end

  defp valid_expression?(_), do: false

  def policy_types, do: @policy_types
  def enforcement_modes, do: @enforcement_modes
end
