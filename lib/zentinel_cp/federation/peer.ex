defmodule ZentinelCp.Federation.Peer do
  @moduledoc """
  Schema for federation peer control planes.

  ## Roles
  - `hub` — central control plane that aggregates state from spokes
  - `spoke` — regional control plane that manages local nodes

  ## Sync Status
  - `pending` — never synced
  - `syncing` — sync in progress
  - `synced` — last sync succeeded
  - `error` — last sync failed
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(hub spoke)
  @sync_statuses ~w(pending syncing synced error)

  schema "federation_peers" do
    field :name, :string
    field :url, :string
    field :role, :string, default: "spoke"
    field :region, :string
    field :tls_cert_pem, :string
    field :api_key_hash, :string
    field :sync_status, :string, default: "pending"
    field :last_sync_at, :utc_datetime
    field :last_sync_error, :string
    field :metadata, :map, default: %{}
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(peer, attrs) do
    peer
    |> cast(attrs, [
      :name,
      :url,
      :role,
      :region,
      :tls_cert_pem,
      :api_key_hash,
      :sync_status,
      :last_sync_at,
      :last_sync_error,
      :metadata,
      :enabled
    ])
    |> validate_required([:name, :url, :role, :region])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:sync_status, @sync_statuses)
    |> validate_format(:url, ~r/^https?:\/\//)
    |> unique_constraint(:url)
  end

  def roles, do: @roles
  def sync_statuses, do: @sync_statuses
end
