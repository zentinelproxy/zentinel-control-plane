defmodule ZentinelCp.Auth.SigningKey do
  @moduledoc """
  OrgSigningKey schema — Ed25519 key pair used for JWT issuance.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "org_signing_keys" do
    field :key_id, :string
    field :public_key, :binary
    field :private_key_encrypted, :binary, redact: true
    field :algorithm, :string, default: "Ed25519"
    field :active, :boolean, default: true
    field :expires_at, :utc_datetime

    belongs_to :org, ZentinelCp.Orgs.Org

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a signing key.
  """
  def create_changeset(key, attrs) do
    key
    |> cast(attrs, [
      :org_id,
      :key_id,
      :public_key,
      :private_key_encrypted,
      :algorithm,
      :active,
      :expires_at
    ])
    |> validate_required([:org_id, :key_id, :public_key, :private_key_encrypted])
    |> unique_constraint(:key_id)
    |> foreign_key_constraint(:org_id)
  end
end
