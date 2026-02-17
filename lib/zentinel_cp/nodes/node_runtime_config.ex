defmodule ZentinelCp.Nodes.NodeRuntimeConfig do
  @moduledoc """
  NodeRuntimeConfig schema for storing the latest KDL config per node.
  One row per node, upserted on each config push.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "node_runtime_configs" do
    field :config_kdl, :string
    field :config_hash, :string

    belongs_to :node, ZentinelCp.Nodes.Node

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a runtime config record.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:node_id, :config_kdl, :config_hash])
    |> validate_required([:node_id, :config_kdl, :config_hash])
    |> unique_constraint(:node_id)
    |> foreign_key_constraint(:node_id)
  end
end
