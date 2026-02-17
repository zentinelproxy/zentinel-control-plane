defmodule ZentinelCp.Nodes.NodeEvent do
  @moduledoc """
  NodeEvent schema for structured event logs per node.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(config_reload bundle_switch error startup shutdown warning info)
  @severities ~w(debug info warn error)

  schema "node_events" do
    field :event_type, :string
    field :severity, :string, default: "info"
    field :message, :string
    field :metadata, :map, default: %{}

    belongs_to :node, ZentinelCp.Nodes.Node

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for recording a node event.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:node_id, :event_type, :severity, :message, :metadata])
    |> validate_required([:node_id, :event_type, :message])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:node_id)
  end
end
