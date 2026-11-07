defmodule ZentinelCp.Services.CertificateCrypto do
  @moduledoc """
  Handles encryption and decryption of certificate private keys at rest.
  See `ZentinelCp.Auth.Encryption` for the key handling.
  """

  alias ZentinelCp.Auth.Encryption

  @aad "zentinel-cert-key"

  @doc "AAD for certificate keys, for code that re-encrypts stored values."
  def aad, do: @aad

  @doc """
  Encrypts a private key PEM string, returning the encrypted binary.
  """
  def encrypt(plaintext) when is_binary(plaintext), do: Encryption.encrypt(plaintext, @aad)

  @doc """
  Decrypts an encrypted private key binary, returning the plaintext PEM string.
  """
  def decrypt(encrypted) when is_binary(encrypted) do
    case Encryption.decrypt(encrypted, @aad) do
      nil -> {:error, :decryption_failed}
      plaintext -> {:ok, plaintext}
    end
  end
end
