defmodule ZentinelCp.Services.InternalCa do
  @moduledoc """
  Schema for project-scoped internal Certificate Authority.

  Each project can have at most one internal CA, used to issue client
  certificates for mutual TLS authentication.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active rotated destroyed)
  @algorithms ~w(EC-P384 RSA-2048)

  schema "internal_cas" do
    field :name, :string
    field :slug, :string
    field :ca_cert_pem, :string
    field :ca_key_encrypted, :binary
    field :key_algorithm, :string, default: "EC-P384"
    field :subject_cn, :string
    field :not_before, :utc_datetime
    field :not_after, :utc_datetime
    field :fingerprint_sha256, :string
    field :next_serial, :integer, default: 1
    field :crl_pem, :string
    field :crl_updated_at, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :issued_certificates, ZentinelCp.Services.IssuedCertificate

    timestamps(type: :utc_datetime)
  end

  def create_changeset(ca, attrs) do
    ca
    |> cast(attrs, [
      :name,
      :subject_cn,
      :key_algorithm,
      :ca_cert_pem,
      :ca_key_encrypted,
      :not_before,
      :not_after,
      :fingerprint_sha256,
      :project_id
    ])
    |> validate_required([:name, :subject_cn, :ca_cert_pem, :ca_key_encrypted, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:key_algorithm, @algorithms)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint(:project_id, message: "already has an internal CA")
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(ca, attrs) do
    ca
    |> cast(attrs, [:name, :status])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:status, @statuses)
  end

  def crl_changeset(ca, attrs) do
    ca
    |> cast(attrs, [:crl_pem, :crl_updated_at])
  end

  def serial_changeset(ca, attrs) do
    ca
    |> cast(attrs, [:next_serial])
    |> validate_required([:next_serial])
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
