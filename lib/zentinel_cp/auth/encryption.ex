defmodule ZentinelCp.Auth.Encryption do
  @moduledoc """
  AES-256-GCM encryption for secrets stored in the database.

  Keys come from `config :zentinel_cp, :encryption_keys`, a list of 32-byte
  binaries set from `ENCRYPTION_KEY` and `ENCRYPTION_KEYS_OLD` in production.
  The first key encrypts; all of them decrypt, which allows rotation. Without
  configured keys (development and test), a key is derived from
  `secret_key_base`.

  Ciphertext format: `"ZE1" <> key_id (4) <> iv (12) <> tag (16) <> ciphertext`.

  Data written before this format has no prefix and was encrypted with a key
  derived from `secret_key_base`. It can still be read, and
  `ZentinelCp.Release.reencrypt_secrets/0` upgrades it.
  """

  @prefix "ZE1"
  @aad "ZentinelCp.Auth.Encryption"

  @doc "Encrypts `plaintext`. `aad` must be the same when decrypting."
  def encrypt(plaintext, aad \\ @aad) when is_binary(plaintext) do
    key = current_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)

    @prefix <> key_id(key) <> iv <> tag <> ciphertext
  end

  @doc "Decrypts `encrypted`, returning the plaintext or `nil` if it cannot be decrypted."
  def decrypt(encrypted, aad \\ @aad)

  def decrypt(
        <<@prefix, id::binary-4, iv::binary-12, tag::binary-16, ciphertext::binary>> = encrypted,
        aad
      ) do
    case Enum.find(keys(), &(key_id(&1) == id)) do
      nil -> decrypt_legacy(encrypted, aad)
      key -> open(key, iv, tag, ciphertext, aad) || decrypt_legacy(encrypted, aad)
    end
  end

  def decrypt(encrypted, aad), do: decrypt_legacy(encrypted, aad)

  @doc "Returns true when the value is in the current format and uses the current key."
  def current?(<<@prefix, id::binary-4, _rest::binary>>), do: id == key_id(current_key())
  def current?(_), do: false

  @doc "Returns true when the value has the versioned ciphertext prefix."
  def encrypted?(<<@prefix, _rest::binary>>), do: true
  def encrypted?(_), do: false

  defp decrypt_legacy(<<iv::binary-12, tag::binary-16, ciphertext::binary>>, aad) do
    open(legacy_key(), iv, tag, ciphertext, aad)
  end

  defp decrypt_legacy(_, _), do: nil

  defp open(key, iv, tag, ciphertext, aad) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false) do
      plaintext when is_binary(plaintext) -> plaintext
      :error -> nil
    end
  end

  defp current_key, do: hd(keys())

  defp keys do
    case Application.get_env(:zentinel_cp, :encryption_keys) do
      [_ | _] = keys -> keys
      _ -> [legacy_key()]
    end
  end

  defp key_id(key), do: binary_part(:crypto.hash(:sha256, key), 0, 4)

  defp legacy_key do
    secret_key_base = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, secret_key_base)
  end
end
