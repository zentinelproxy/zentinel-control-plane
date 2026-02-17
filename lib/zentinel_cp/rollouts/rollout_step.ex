defmodule ZentinelCp.Rollouts.RolloutStep do
  @moduledoc """
  RolloutStep schema representing a single batch in a rollout.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(pending running verifying validating completed failed)

  schema "rollout_steps" do
    field :step_index, :integer
    field :node_ids, {:array, :string}, default: []
    field :state, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error, :map
    field :deployment_slot, :string
    field :traffic_weight, :integer
    field :validated_at, :utc_datetime
    field :health_gate_failure_since, :utc_datetime

    belongs_to :rollout, ZentinelCp.Rollouts.Rollout

    timestamps(type: :utc_datetime)
  end

  def create_changeset(step, attrs) do
    step
    |> cast(attrs, [:rollout_id, :step_index, :node_ids, :deployment_slot, :traffic_weight])
    |> validate_required([:rollout_id, :step_index, :node_ids])
    |> validate_number(:step_index, greater_than_or_equal_to: 0)
    |> put_change(:state, "pending")
    |> unique_constraint([:rollout_id, :step_index])
    |> foreign_key_constraint(:rollout_id)
  end

  def state_changeset(step, state, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      %{state: state}
      |> maybe_set_started_at(state, step, now)
      |> maybe_set_completed_at(state, now)
      |> maybe_set_validated_at(state, now)
      |> maybe_set_error(opts[:error])

    step
    |> change(changes)
    |> validate_inclusion(:state, @states)
  end

  defp maybe_set_started_at(changes, "running", %{started_at: nil}, now) do
    Map.put(changes, :started_at, now)
  end

  defp maybe_set_started_at(changes, _state, _step, _now), do: changes

  defp maybe_set_completed_at(changes, state, now) when state in ~w(completed failed) do
    Map.put(changes, :completed_at, now)
  end

  defp maybe_set_completed_at(changes, _state, _now), do: changes

  defp maybe_set_validated_at(changes, "validating", now) do
    Map.put(changes, :validated_at, now)
  end

  defp maybe_set_validated_at(changes, _state, _now), do: changes

  defp maybe_set_error(changes, nil), do: changes
  defp maybe_set_error(changes, error), do: Map.put(changes, :error, error)
end
