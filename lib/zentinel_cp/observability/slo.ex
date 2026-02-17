defmodule ZentinelCp.Observability.Slo do
  @moduledoc """
  Schema for Service Level Objectives.

  An SLO defines a target level of reliability for a service,
  measured by a specific SLI type over a rolling window.

  ## SLI Types
  - `availability` — percentage of non-5xx responses (target e.g. 99.9)
  - `latency_p99` — p99 latency must be below threshold in ms (target e.g. 200)
  - `latency_p95` — p95 latency must be below threshold in ms
  - `error_rate` — error rate must be below threshold percentage (target e.g. 1.0)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sli_types ~w(availability latency_p99 latency_p95 error_rate)

  schema "slos" do
    field :name, :string
    field :description, :string
    field :sli_type, :string
    field :target, :float
    field :window_days, :integer, default: 30
    field :enabled, :boolean, default: true
    field :burn_rate, :float
    field :error_budget_remaining, :float
    field :last_computed_at, :utc_datetime

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :service, ZentinelCp.Services.Service

    timestamps(type: :utc_datetime)
  end

  def changeset(slo, attrs) do
    slo
    |> cast(attrs, [
      :project_id,
      :service_id,
      :name,
      :description,
      :sli_type,
      :target,
      :window_days,
      :enabled,
      :burn_rate,
      :error_budget_remaining,
      :last_computed_at
    ])
    |> validate_required([:project_id, :name, :sli_type, :target])
    |> validate_inclusion(:sli_type, @sli_types)
    |> validate_number(:target, greater_than: 0)
    |> validate_number(:window_days, greater_than: 0)
    |> validate_target_range()
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:service_id)
  end

  defp validate_target_range(changeset) do
    sli_type = get_field(changeset, :sli_type)
    target = get_field(changeset, :target)

    case {sli_type, target} do
      {"availability", t} when is_number(t) and (t <= 0 or t > 100) ->
        add_error(changeset, :target, "must be between 0 and 100 for availability")

      {"error_rate", t} when is_number(t) and (t <= 0 or t > 100) ->
        add_error(changeset, :target, "must be between 0 and 100 for error_rate")

      _ ->
        changeset
    end
  end

  def sli_types, do: @sli_types
end
