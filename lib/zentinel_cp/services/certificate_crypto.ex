defmodule ZentinelCp.Services.CertificateCrypto do
  @moduledoc """
  Handles encryption and decryption of certificate private keys at rest.

  Uses AES-256-GCM with a key derived from the application's secret_key_base.
  """

  @aad "zentinel-cert-key"

  @doc """
  Encrypts a private key PEM string, returning the encrypted binary.
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = derive_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  @doc """
  Decrypts an encrypted private key binary, returning the plaintext PEM string.
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
    secret = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, secret)
  end
end
