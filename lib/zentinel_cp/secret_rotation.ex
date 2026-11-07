defmodule ZentinelCp.SecretRotation do
  @moduledoc """
  Rewrites stored secrets under the current encryption key.

  This upgrades values written before encryption or before `ENCRYPTION_KEY`
  existed, and moves values off a retired key. Remove the old key from
  `ENCRYPTION_KEYS_OLD` only after this has run.
  """

  import Ecto.Query

  alias ZentinelCp.Auth.{Encryption, OidcProvider, SigningKey}
  alias ZentinelCp.Accounts.UserTotp
  alias ZentinelCp.Events.Channel
  alias ZentinelCp.Federation.RegionalStorage
  alias ZentinelCp.Repo
  alias ZentinelCp.Secrets.{Secret, SecretCrypto, VaultConfig}
  alias ZentinelCp.Services.{Certificate, CertificateCrypto, InternalCa, IssuedCertificate}

  # Fields whose Ecto type encrypts on write: rewriting the value upgrades it.
  @typed_fields [
    {SigningKey, :private_key_encrypted},
    {UserTotp, :secret},
    {Channel, :config},
    {Channel, :signing_secret},
    {RegionalStorage, :secret_access_key_encrypted}
  ]

  # Binary columns encrypted by the caller.
  @raw_fields [
    {OidcProvider, :client_secret_encrypted, nil},
    {Secret, :encrypted_value, :secret},
    {VaultConfig, :auth_config, :secret},
    {Certificate, :key_pem_encrypted, :certificate},
    {Certificate, :acme_account_key_encrypted, :certificate},
    {InternalCa, :ca_key_encrypted, :certificate},
    {IssuedCertificate, :key_pem_encrypted, :certificate}
  ]

  @doc "Rewrites all stored secrets. Returns the number of values rewritten per field."
  def run do
    typed = Enum.map(@typed_fields, fn {schema, field} -> rotate_typed(schema, field) end)
    raw = Enum.map(@raw_fields, fn {schema, field, kind} -> rotate_raw(schema, field, kind) end)
    typed ++ raw
  end

  defp rotate_typed(schema, field) do
    rows =
      from(r in schema, where: not is_nil(field(r, ^field)), select: {r.id, field(r, ^field)})
      |> Repo.all()

    Enum.each(rows, fn {id, value} ->
      from(r in schema, where: r.id == ^id) |> Repo.update_all(set: [{field, value}])
    end)

    {schema, field, length(rows)}
  end

  defp rotate_raw(schema, field, kind) do
    aad = aad(kind)

    count =
      from(r in schema, where: not is_nil(field(r, ^field)), select: {r.id, field(r, ^field)})
      |> Repo.all()
      |> Enum.reject(fn {_id, value} -> Encryption.current?(value) end)
      |> Enum.map(fn {id, value} ->
        case Encryption.decrypt(value, aad) do
          nil ->
            raise "cannot decrypt #{inspect(schema)}.#{field} for #{id}: is a key missing?"

          plaintext ->
            from(r in schema, where: r.id == ^id)
            |> Repo.update_all(set: [{field, Encryption.encrypt(plaintext, aad)}])
        end
      end)
      |> length()

    {schema, field, count}
  end

  defp aad(nil), do: "ZentinelCp.Auth.Encryption"
  defp aad(:secret), do: SecretCrypto.aad()
  defp aad(:certificate), do: CertificateCrypto.aad()
end
