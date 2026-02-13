defmodule SentinelCp.Services.TrustStore do
  @moduledoc """
  Trust store schema for CA certificate bundles used to verify upstream servers.

  Trust stores hold one or more CA certificates in PEM format. When linked to an
  upstream group, the proxy uses these CAs to verify TLS connections to backends.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trust_stores" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :certificates_pem, :string
    field :cert_count, :integer, default: 0
    field :subjects, {:array, :string}, default: []
    field :earliest_expiry, :utc_datetime
    field :latest_expiry, :utc_datetime

    belongs_to :project, SentinelCp.Projects.Project
    has_many :upstream_groups, SentinelCp.Services.UpstreamGroup

    timestamps(type: :utc_datetime)
  end

  def create_changeset(trust_store, attrs) do
    trust_store
    |> cast(attrs, [:name, :description, :certificates_pem, :project_id])
    |> validate_required([:name, :certificates_pem, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_pem_bundle()
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(trust_store, attrs) do
    trust_store
    |> cast(attrs, [:name, :description, :certificates_pem])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> maybe_revalidate_pem()
  end

  # Validate the PEM bundle and extract metadata when certificates_pem changes
  defp validate_pem_bundle(changeset) do
    case get_change(changeset, :certificates_pem) do
      nil ->
        changeset

      pem ->
        case parse_pem_bundle(pem) do
          {:ok, meta} ->
            changeset
            |> put_change(:cert_count, meta.cert_count)
            |> put_change(:subjects, meta.subjects)
            |> put_change(:earliest_expiry, meta.earliest_expiry)
            |> put_change(:latest_expiry, meta.latest_expiry)

          {:error, reason} ->
            add_error(changeset, :certificates_pem, reason)
        end
    end
  end

  defp maybe_revalidate_pem(changeset) do
    if get_change(changeset, :certificates_pem) do
      validate_pem_bundle(changeset)
    else
      changeset
    end
  end

  @doc false
  def parse_pem_bundle(pem) when is_binary(pem) do
    entries = :public_key.pem_decode(pem)

    cert_entries =
      Enum.filter(entries, fn
        {:Certificate, _der, _} -> true
        _ -> false
      end)

    if cert_entries == [] do
      {:error, "PEM bundle must contain at least one certificate"}
    else
      certs =
        Enum.map(cert_entries, fn {:Certificate, der, _} ->
          cert = :public_key.pkix_decode_cert(der, :otp)
          tbs = elem(cert, 1)
          validity = elem(tbs, 5)
          not_before = parse_asn1_time(elem(validity, 1))
          not_after = parse_asn1_time(elem(validity, 2))
          subject = extract_cn(elem(tbs, 6))

          %{subject: subject, not_before: not_before, not_after: not_after}
        end)

      subjects = certs |> Enum.map(& &1.subject) |> Enum.reject(&is_nil/1)
      expiries = certs |> Enum.map(& &1.not_after) |> Enum.reject(&is_nil/1)

      earliest_expiry = if expiries != [], do: Enum.min(expiries, DateTime), else: nil
      latest_expiry = if expiries != [], do: Enum.max(expiries, DateTime), else: nil

      {:ok,
       %{
         cert_count: length(cert_entries),
         subjects: subjects,
         earliest_expiry: earliest_expiry,
         latest_expiry: latest_expiry
       }}
    end
  rescue
    _ -> {:error, "invalid PEM data"}
  end

  defp parse_asn1_time({:utcTime, time}) do
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
