defmodule ZentinelCp.Auth.Encryption do
  @moduledoc """
  Simple symmetric encryption for storing sensitive values (client secrets, etc.)
  using AES-256-GCM with the application's secret key base.
  """

  @aad "ZentinelCp.Auth.Encryption"

  def encrypt(plaintext) when is_binary(plaintext) do
    key = encryption_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  def decrypt(<<iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    key = encryption_key()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> plaintext
      :error -> nil
    end
  end

  def decrypt(_), do: nil

  defp encryption_key do
    secret_key_base =
      Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:secret_key_base]

    :crypto.hash(:sha256, secret_key_base)
  end
end
