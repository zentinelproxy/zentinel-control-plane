defmodule ZentinelCp.Nodes.NodeGroup do
  @moduledoc """
  Schema for node groups.

  Node groups provide a way to organize nodes beyond labels,
  allowing for more flexible targeting in rollouts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "node_groups" do
    field :name, :string
    field :description, :string
    field :color, :string, default: "#6366f1"

    belongs_to :project, ZentinelCp.Projects.Project

    many_to_many :nodes, ZentinelCp.Nodes.Node,
      join_through: ZentinelCp.Nodes.NodeGroupMembership,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a node group.
  """
  def create_changeset(node_group, attrs) do
    node_group
    |> cast(attrs, [:name, :description, :color, :project_id])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a valid hex color")
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a node group.
  """
  def update_changeset(node_group, attrs) do
    node_group
    |> cast(attrs, [:name, :description, :color])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a valid hex color")
    |> unique_constraint([:project_id, :name])
  end
end
