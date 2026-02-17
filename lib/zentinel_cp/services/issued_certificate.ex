defmodule ZentinelCp.Services.IssuedCertificate do
  @moduledoc """
  Schema for certificates issued by an internal CA.

  Tracks client certificates for mutual TLS authentication,
  including their revocation status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issued_certificates" do
    field :name, :string
    field :slug, :string
    field :serial_number, :integer
    field :subject_cn, :string
    field :subject_ou, :string
    field :cert_pem, :string
    field :key_pem_encrypted, :binary
    field :not_before, :utc_datetime
    field :not_after, :utc_datetime
    field :fingerprint_sha256, :string
    field :key_usage, :string, default: "clientAuth"
    field :status, :string, default: "active"
    field :revoked_at, :utc_datetime
    field :revoke_reason, :string

    belongs_to :internal_ca, ZentinelCp.Services.InternalCa

    timestamps(type: :utc_datetime)
  end

  def create_changeset(cert, attrs) do
    cert
    |> cast(attrs, [
      :name,
      :serial_number,
      :subject_cn,
      :subject_ou,
      :cert_pem,
      :key_pem_encrypted,
      :not_before,
      :not_after,
      :fingerprint_sha256,
      :key_usage,
      :internal_ca_id
    ])
    |> validate_required([
      :name,
      :serial_number,
      :subject_cn,
      :cert_pem,
      :key_pem_encrypted,
      :internal_ca_id
    ])
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:internal_ca_id, :serial_number],
      error_key: :serial_number,
      message: "has already been taken"
    )
    |> unique_constraint([:internal_ca_id, :slug],
      error_key: :slug,
      message: "has already been taken"
    )
    |> foreign_key_constraint(:internal_ca_id)
  end

  def revoke_changeset(cert, attrs) do
    cert
    |> cast(attrs, [:revoked_at, :revoke_reason])
    |> put_change(:status, "revoked")
    |> validate_required([:revoked_at])
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 50)
  end
end
