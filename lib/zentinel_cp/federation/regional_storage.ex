defmodule ZentinelCp.Federation.RegionalStorage do
  @moduledoc """
  Schema for region-specific S3/MinIO storage configuration.

  Each spoke region can have its own storage bucket so nodes pull
  bundles from the nearest endpoint.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "regional_storages" do
    field :region, :string
    field :bucket, :string
    field :endpoint, :string
    field :access_key_id, :string
    field :secret_access_key_encrypted, :binary
    field :enabled, :boolean, default: true

    belongs_to :peer, ZentinelCp.Federation.Peer

    timestamps(type: :utc_datetime)
  end

  def changeset(storage, attrs) do
    storage
    |> cast(attrs, [
      :peer_id,
      :region,
      :bucket,
      :endpoint,
      :access_key_id,
      :secret_access_key_encrypted,
      :enabled
    ])
    |> validate_required([:region, :bucket, :endpoint])
    |> unique_constraint(:region)
    |> foreign_key_constraint(:peer_id)
  end
end
