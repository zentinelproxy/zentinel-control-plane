defmodule SentinelCp.Services.Certificate do
  @moduledoc """
  Certificate schema for TLS certificate management.

  Stores certificates with encrypted private keys for proxy TLS termination.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SentinelCp.Services.CertificateCrypto

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active expiring_soon expired revoked)

  schema "certificates" do
    field :name, :string
    field :slug, :string
    field :domain, :string
    field :san_domains, {:array, :string}, default: []
    field :cert_pem, :string
    field :key_pem_encrypted, :binary
    field :ca_chain_pem, :string
    field :issuer, :string
    field :not_before, :utc_datetime
    field :not_after, :utc_datetime
    field :fingerprint_sha256, :string
    field :auto_renew, :boolean, default: false
    field :acme_config, :map, default: %{}
    field :status, :string, default: "active"
    field :acme_account_key_encrypted, :binary
    field :last_renewal_at, :utc_datetime
    field :last_renewal_error, :string

    belongs_to :project, SentinelCp.Projects.Project
    has_many :services, SentinelCp.Services.Service

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a certificate. Expects `:key_pem` in attrs (plaintext),
  which will be encrypted before storage.
  """
  def create_changeset(cert, attrs) do
    cert
    |> cast(attrs, [
      :name,
      :domain,
      :san_domains,
      :cert_pem,
      :ca_chain_pem,
      :auto_renew,
      :acme_config,
      :project_id
    ])
    |> validate_required([:name, :domain, :cert_pem, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:status, @statuses)
    |> encrypt_key(attrs)
    |> extract_cert_metadata()
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating certificate metadata (name, auto_renew, acme_config).
  """
  def update_changeset(cert, attrs) do
    cert
    |> cast(attrs, [:name, :auto_renew, :acme_config, :status])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for renewing a certificate (new cert_pem, key, dates).
  """
  def renew_changeset(cert, attrs) do
    cert
    |> cast(attrs, [:cert_pem, :ca_chain_pem])
    |> validate_required([:cert_pem])
    |> encrypt_key(attrs)
    |> extract_cert_metadata()
    |> put_change(:status, "active")
  end

  @doc """
  Changeset for updating ACME-specific fields (account key, renewal status).
  """
  def acme_changeset(cert, attrs) do
    cert
    |> cast(attrs, [:acme_account_key_encrypted, :last_renewal_at, :last_renewal_error, :auto_renew, :acme_config])
  end

  @doc """
  Returns true if the certificate expires within `days` days.
  """
  def expires_soon?(%__MODULE__{not_after: nil}), do: false

  def expires_soon?(%__MODULE__{not_after: not_after}, days \\ 30) do
    threshold = DateTime.utc_now() |> DateTime.add(days * 86400, :second)
    DateTime.compare(not_after, threshold) in [:lt, :eq]
  end

  @doc """
  Returns true if the certificate has expired.
  """
  def expired?(%__MODULE__{not_after: nil}), do: false

  def expired?(%__MODULE__{not_after: not_after}) do
    DateTime.compare(not_after, DateTime.utc_now()) in [:lt, :eq]
  end

  # Encrypt the private key PEM if provided in attrs
  defp encrypt_key(changeset, attrs) do
    key_pem = attrs[:key_pem] || attrs["key_pem"]

    if key_pem && is_binary(key_pem) && key_pem != "" do
      encrypted = CertificateCrypto.encrypt(key_pem)
      put_change(changeset, :key_pem_encrypted, encrypted)
    else
      # key_pem is required on create
      if changeset.data.id == nil do
        add_error(changeset, :key_pem_encrypted, "private key is required")
      else
        changeset
      end
    end
  end

  # Extract metadata from the certificate PEM
  defp extract_cert_metadata(changeset) do
    case get_change(changeset, :cert_pem) do
      nil ->
        changeset

      cert_pem ->
        case parse_cert_pem(cert_pem) do
          {:ok, meta} ->
            changeset
            |> put_change(:issuer, meta.issuer)
            |> put_change(:not_before, meta.not_before)
            |> put_change(:not_after, meta.not_after)
            |> put_change(:fingerprint_sha256, meta.fingerprint_sha256)
            |> maybe_put_domain(meta.domain)
            |> maybe_put_san_domains(meta.san_domains)

          {:error, _reason} ->
            add_error(changeset, :cert_pem, "invalid certificate PEM")
        end
    end
  end

  defp maybe_put_domain(changeset, nil), do: changeset

  defp maybe_put_domain(changeset, domain) do
    # Only set from cert if not already provided
    if get_field(changeset, :domain) in [nil, ""] do
      put_change(changeset, :domain, domain)
    else
      changeset
    end
  end

  defp maybe_put_san_domains(changeset, []), do: changeset

  defp maybe_put_san_domains(changeset, san_domains) do
    if get_field(changeset, :san_domains) in [nil, []] do
      put_change(changeset, :san_domains, san_domains)
    else
      changeset
    end
  end

  @doc false
  def parse_cert_pem(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, der, _} | _] ->
        # OTPCertificate record: {OTPCertificate, TBSCertificate, SignatureAlgorithm, Signature}
        cert = :public_key.pkix_decode_cert(der, :otp)
        # TBS is at index 1 (index 0 is the record tag :OTPCertificate)
        tbs = elem(cert, 1)

        # OTPTBSCertificate record fields (0-indexed):
        # 0=tag, 1=version, 2=serialNumber, 3=signature, 4=issuer, 5=validity, 6=subject,
        # 7=subjectPublicKeyInfo, 8=issuerUniqueID, 9=subjectUniqueID, 10=extensions
        validity = elem(tbs, 5)
        not_before = parse_asn1_time(elem(validity, 1))
        not_after = parse_asn1_time(elem(validity, 2))

        issuer = extract_issuer(elem(tbs, 4))
        domain = extract_cn(elem(tbs, 6))
        san_domains = extract_san_domains(tbs)

        fingerprint =
          :crypto.hash(:sha256, der)
          |> Base.encode16(case: :lower)
          |> String.graphemes()
          |> Enum.chunk_every(2)
          |> Enum.map_join(":", &Enum.join/1)

        {:ok,
         %{
           issuer: issuer,
           domain: domain,
           san_domains: san_domains,
           not_before: not_before,
           not_after: not_after,
           fingerprint_sha256: fingerprint
         }}

      _ ->
        {:error, :invalid_pem}
    end
  rescue
    _ -> {:error, :parse_error}
  end

  defp parse_asn1_time({:utcTime, time}) do
    # Format: 'YYMMDDHHMMSSZ'
    time_str = to_string(time)

    year =
      case String.slice(time_str, 0, 2) do
        y ->
          yi = String.to_integer(y)
          if yi >= 50, do: 1900 + yi, else: 2000 + yi
      end

    month = String.to_integer(String.slice(time_str, 2, 2))
    day = String.to_integer(String.slice(time_str, 4, 2))
    hour = String.to_integer(String.slice(time_str, 6, 2))
    minute = String.to_integer(String.slice(time_str, 8, 2))
    second = String.to_integer(String.slice(time_str, 10, 2))

    {:ok, dt} = DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second))
    DateTime.truncate(dt, :second)
  end

  defp parse_asn1_time({:generalTime, time}) do
    # Format: 'YYYYMMDDHHMMSSZ'
    time_str = to_string(time)
    year = String.to_integer(String.slice(time_str, 0, 4))
    month = String.to_integer(String.slice(time_str, 4, 2))
    day = String.to_integer(String.slice(time_str, 6, 2))
    hour = String.to_integer(String.slice(time_str, 8, 2))
    minute = String.to_integer(String.slice(time_str, 10, 2))
    second = String.to_integer(String.slice(time_str, 12, 2))

    {:ok, dt} = DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second))
    DateTime.truncate(dt, :second)
  end

  defp extract_issuer({:rdnSequence, rdn_seq}) do
    rdn_seq
    |> List.flatten()
    |> Enum.find_value(fn
      {:AttributeTypeAndValue, {2, 5, 4, 3}, value} ->
        extract_string_value(value)

      {:AttributeTypeAndValue, {2, 5, 4, 10}, value} ->
        extract_string_value(value)

      _ ->
        nil
    end)
  end

  defp extract_issuer(_), do: nil

  defp extract_cn({:rdnSequence, rdn_seq}) do
    rdn_seq
    |> List.flatten()
    |> Enum.find_value(fn
      {:AttributeTypeAndValue, {2, 5, 4, 3}, value} ->
        extract_string_value(value)

      _ ->
        nil
    end)
  end

  defp extract_cn(_), do: nil

  defp extract_string_value({:utf8String, value}), do: to_string(value)
  defp extract_string_value({:printableString, value}), do: to_string(value)
  defp extract_string_value(value) when is_binary(value), do: value
  defp extract_string_value(value) when is_list(value), do: to_string(value)
  defp extract_string_value(_), do: nil

  defp extract_san_domains(tbs) do
    # Extensions are at index 10 in the OTPTBSCertificate record
    extensions =
      try do
        elem(tbs, 10)
      rescue
        _ -> nil
      end

    case extensions do
      :asn1_NOVALUE ->
        []

      nil ->
        []

      exts when is_list(exts) ->
        exts
        |> Enum.find_value([], fn
          {:Extension, {2, 5, 29, 17}, _critical, san_value} ->
            parse_san_value(san_value)

          _ ->
            nil
        end)
    end
  end

  defp parse_san_value(value) when is_list(value) do
    value
    |> Enum.flat_map(fn
      {:dNSName, name} -> [to_string(name)]
      _ -> []
    end)
  end

  defp parse_san_value(_), do: []

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
