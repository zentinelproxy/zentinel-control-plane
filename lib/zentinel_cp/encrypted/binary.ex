defmodule ZentinelCp.Encrypted.Binary do
  @moduledoc """
  Ecto type that stores a binary encrypted and exposes it decrypted.

  Rows written before encryption was added hold the raw value, which is
  returned as is until `ZentinelCp.Release.reencrypt_secrets/0` upgrades it.
  """
  use Ecto.Type

  alias ZentinelCp.Auth.Encryption

  @aad "ZentinelCp.Encrypted.Binary"

  def type, do: :binary

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  def dump(value) when is_binary(value), do: {:ok, Encryption.encrypt(value, @aad)}
  def dump(_), do: :error

  def load(value) when is_binary(value) do
    if Encryption.encrypted?(value) do
      case Encryption.decrypt(value, @aad) do
        nil -> :error
        plaintext -> {:ok, plaintext}
      end
    else
      {:ok, value}
    end
  end

  def load(_), do: :error
end
