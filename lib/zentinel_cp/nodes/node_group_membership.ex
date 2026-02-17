defmodule ZentinelCp.Nodes.NodeGroupMembership do
  @moduledoc """
  Schema for node group memberships.

  Links nodes to node groups in a many-to-many relationship.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "node_group_memberships" do
    belongs_to :node, ZentinelCp.Nodes.Node
    belongs_to :node_group, ZentinelCp.Nodes.NodeGroup

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:node_id, :node_group_id])
    |> validate_required([:node_id, :node_group_id])
    |> unique_constraint([:node_id, :node_group_id])
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:node_group_id)
  end
end
