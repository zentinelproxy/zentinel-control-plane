defmodule SentinelCp.Secrets.SecretCrypto do
  @moduledoc """
  Handles encryption and decryption of secrets at rest.

  Uses AES-256-GCM with a key derived from the application's secret_key_base.
  Uses a different AAD from CertificateCrypto for domain separation.
  """

  @aad "sentinel-secret"

  @doc """
  Encrypts a plaintext secret value, returning the encrypted binary.
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = derive_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  @doc """
  Decrypts an encrypted secret binary, returning the plaintext value.
  """
  def decrypt(encrypted) when is_binary(encrypted) do
    key = derive_key()
    <<iv::binary-12, tag::binary-16, ciphertext::binary>> = encrypted

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :decryption_failed}
    end
  end

  defp derive_key do
    secret = Application.get_env(:sentinel_cp, SentinelCpWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, secret)
  end
end
