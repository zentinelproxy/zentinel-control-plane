defmodule ZentinelCp.Observability.AlertRule do
  @moduledoc """
  Schema for declarative alert rules.

  ## Rule Types
  - `metric` — fires when a metric exceeds a threshold
  - `slo` — fires when SLO error budget burn rate exceeds threshold
  - `threshold` — generic threshold comparison

  ## Condition Format
  ```json
  {
    "metric": "error_rate",
    "operator": ">",
    "value": 5.0,
    "service_id": "optional-uuid"
  }
  ```

  ## Severity Levels
  - `critical` — page immediately
  - `warning` — alert but don't page
  - `info` — informational
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rule_types ~w(metric slo threshold)
  @severities ~w(critical warning info)

  schema "alert_rules" do
    field :name, :string
    field :description, :string
    field :rule_type, :string
    field :condition, :map
    field :severity, :string, default: "warning"
    field :for_seconds, :integer, default: 0
    field :channel_ids, {:array, :binary_id}, default: []
    field :enabled, :boolean, default: true
    field :silenced_until, :utc_datetime
    field :labels, :map, default: %{}

    belongs_to :project, ZentinelCp.Projects.Project

    has_many :alert_states, ZentinelCp.Observability.AlertState

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :project_id,
      :name,
      :description,
      :rule_type,
      :condition,
      :severity,
      :for_seconds,
      :channel_ids,
      :enabled,
      :silenced_until,
      :labels
    ])
    |> validate_required([:project_id, :name, :rule_type, :condition])
    |> validate_inclusion(:rule_type, @rule_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_number(:for_seconds, greater_than_or_equal_to: 0)
    |> validate_condition()
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  defp validate_condition(changeset) do
    condition = get_field(changeset, :condition)

    case condition do
      %{"metric" => _, "operator" => op, "value" => _}
      when op in [">", "<", ">=", "<=", "==", "!="] ->
        changeset

      %{"slo_id" => _, "burn_rate_threshold" => _} ->
        changeset

      nil ->
        changeset

      _ ->
        add_error(changeset, :condition, "must contain valid metric or slo condition")
    end
  end

  @doc "Returns whether this alert rule is currently silenced."
  def silenced?(%__MODULE__{silenced_until: nil}), do: false

  def silenced?(%__MODULE__{silenced_until: until}) do
    DateTime.compare(DateTime.utc_now(), until) == :lt
  end

  def rule_types, do: @rule_types
  def severities, do: @severities
end
