defmodule ZentinelCp.Encrypted.String do
  @moduledoc """
  Ecto type for strings stored encrypted in a text column, Base64 encoded.
  Unprefixed values predate encryption and are returned as is.
  """
  use Ecto.Type

  alias ZentinelCp.Auth.Encryption

  @aad "ZentinelCp.Encrypted.String"
  @prefix "enc:v1:"

  def type, do: :string

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  def dump(value) when is_binary(value) do
    {:ok, @prefix <> Base.encode64(Encryption.encrypt(value, @aad))}
  end

  def dump(_), do: :error

  def load(@prefix <> encoded) do
    with {:ok, ciphertext} <- Base.decode64(encoded),
         plaintext when is_binary(plaintext) <- Encryption.decrypt(ciphertext, @aad) do
      {:ok, plaintext}
    else
      _ -> :error
    end
  end

  def load(value) when is_binary(value), do: {:ok, value}
  def load(_), do: :error
end
