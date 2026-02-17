defmodule ZentinelCp.Services.CircuitBreakerStatus do
  @moduledoc """
  Schema for tracking circuit breaker state per upstream group per node.

  State transitions: closed -> open -> half_open -> closed
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(closed open half_open)

  schema "circuit_breaker_statuses" do
    field :state, :string, default: "closed"
    field :failure_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :last_failure_at, :utc_datetime
    field :last_success_at, :utc_datetime
    field :last_trip_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :upstream_group, ZentinelCp.Services.UpstreamGroup
    belongs_to :node, ZentinelCp.Nodes.Node

    timestamps(type: :utc_datetime)
  end

  def changeset(status, attrs) do
    status
    |> cast(attrs, [
      :upstream_group_id,
      :node_id,
      :state,
      :failure_count,
      :success_count,
      :last_failure_at,
      :last_success_at,
      :last_trip_at,
      :metadata
    ])
    |> validate_required([:upstream_group_id, :node_id, :state])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:upstream_group_id, :node_id])
    |> foreign_key_constraint(:upstream_group_id)
    |> foreign_key_constraint(:node_id)
  end
end
