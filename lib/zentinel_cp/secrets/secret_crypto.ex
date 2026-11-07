defmodule ZentinelCp.Secrets.SecretCrypto do
  @moduledoc """
  Handles encryption and decryption of secrets at rest.
  Uses a different AAD from CertificateCrypto for domain separation.
  See `ZentinelCp.Auth.Encryption` for the key handling.
  """

  alias ZentinelCp.Auth.Encryption

  @aad "zentinel-secret"

  @doc "AAD for secrets, for code that re-encrypts stored values."
  def aad, do: @aad

  @doc """
  Encrypts a plaintext secret value, returning the encrypted binary.
  """
  def encrypt(plaintext) when is_binary(plaintext), do: Encryption.encrypt(plaintext, @aad)

  @doc """
  Decrypts an encrypted secret binary, returning the plaintext value.
  """
  def decrypt(encrypted) when is_binary(encrypted) do
    case Encryption.decrypt(encrypted, @aad) do
      nil -> {:error, :decryption_failed}
      plaintext -> {:ok, plaintext}
    end
  end
end
