defmodule ZentinelCp.Nodes.NodeHeartbeat do
  @moduledoc """
  NodeHeartbeat schema for tracking node health history.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "node_heartbeats" do
    field :health, :map, default: %{}
    field :metrics, :map, default: %{}
    field :active_bundle_id, :binary_id
    field :staged_bundle_id, :binary_id

    belongs_to :node, ZentinelCp.Nodes.Node

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for recording a heartbeat.
  """
  def changeset(heartbeat, attrs) do
    heartbeat
    |> cast(attrs, [:node_id, :health, :metrics, :active_bundle_id, :staged_bundle_id])
    |> validate_required([:node_id])
    |> foreign_key_constraint(:node_id)
  end
end
