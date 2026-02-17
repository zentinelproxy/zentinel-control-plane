defmodule ZentinelCp.Audit.AuditLog do
  @moduledoc """
  AuditLog schema for tracking all mutations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actor_types ~w(user api_key system node)

  schema "audit_logs" do
    field :project_id, :binary_id
    field :org_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    # Tamper-evident chain fields
    field :previous_hash, :string
    field :entry_hash, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for an audit log entry.
  """
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :project_id,
      :org_id,
      :actor_type,
      :actor_id,
      :action,
      :resource_type,
      :resource_id,
      :changes,
      :metadata,
      :previous_hash,
      :entry_hash
    ])
    |> validate_required([:actor_type, :action, :resource_type])
    |> validate_inclusion(:actor_type, @actor_types)
  end
end
