defmodule ZentinelCp.Rollouts.NodeBundleStatus do
  @moduledoc """
  NodeBundleStatus schema tracking per-node bundle deployment state during a rollout.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(pending staging staged activating active failed)

  schema "node_bundle_statuses" do
    field :state, :string, default: "pending"
    field :reason, :string
    field :staged_at, :utc_datetime
    field :activated_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :last_report_at, :utc_datetime
    field :error, :map

    belongs_to :node, ZentinelCp.Nodes.Node
    belongs_to :rollout, ZentinelCp.Rollouts.Rollout
    belongs_to :bundle, ZentinelCp.Bundles.Bundle

    timestamps(type: :utc_datetime)
  end

  def create_changeset(status, attrs) do
    status
    |> cast(attrs, [:node_id, :rollout_id, :bundle_id])
    |> validate_required([:node_id, :rollout_id, :bundle_id])
    |> put_change(:state, "pending")
    |> unique_constraint([:node_id, :rollout_id])
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:rollout_id)
    |> foreign_key_constraint(:bundle_id)
  end

  def state_changeset(status, state, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      %{state: state, last_report_at: now}
      |> maybe_set_staged_at(state, now)
      |> maybe_set_activated_at(state, now)
      |> maybe_set_verified_at(state, now)
      |> maybe_set_error(opts[:error])
      |> maybe_set_reason(opts[:reason])

    status
    |> change(changes)
    |> validate_inclusion(:state, @states)
  end

  defp maybe_set_staged_at(changes, "staged", now), do: Map.put(changes, :staged_at, now)
  defp maybe_set_staged_at(changes, _state, _now), do: changes

  defp maybe_set_activated_at(changes, "active", now), do: Map.put(changes, :activated_at, now)
  defp maybe_set_activated_at(changes, _state, _now), do: changes

  defp maybe_set_verified_at(changes, state, now) when state == "active" do
    Map.put(changes, :verified_at, now)
  end

  defp maybe_set_verified_at(changes, _state, _now), do: changes

  defp maybe_set_error(changes, nil), do: changes
  defp maybe_set_error(changes, error), do: Map.put(changes, :error, error)

  defp maybe_set_reason(changes, nil), do: changes
  defp maybe_set_reason(changes, reason), do: Map.put(changes, :reason, reason)
end
