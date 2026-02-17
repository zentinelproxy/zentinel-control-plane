defmodule ZentinelCp.Audit.AuditCheckpoint do
  @moduledoc """
  Schema for periodic signed checkpoints in the tamper-evident audit chain.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_checkpoints" do
    field :sequence_number, :integer
    field :last_entry_id, :binary_id
    field :last_entry_hash, :string
    field :digest, :string
    field :signature, :string
    field :entries_count, :integer
    field :project_id, :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [
      :sequence_number,
      :last_entry_id,
      :last_entry_hash,
      :digest,
      :signature,
      :entries_count,
      :project_id
    ])
    |> validate_required([
      :sequence_number,
      :last_entry_hash,
      :digest,
      :signature,
      :entries_count
    ])
    |> validate_number(:sequence_number, greater_than: 0)
    |> validate_number(:entries_count, greater_than_or_equal_to: 0)
  end
end
