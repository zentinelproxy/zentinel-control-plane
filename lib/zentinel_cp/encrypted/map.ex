defmodule ZentinelCp.Encrypted.Map do
  @moduledoc """
  Ecto type for maps stored encrypted inside a JSON column, as
  `{"__enc__": "<base64>"}`. Other maps predate encryption and are returned as is.
  """
  use Ecto.Type

  alias ZentinelCp.Auth.Encryption

  @aad "ZentinelCp.Encrypted.Map"
  @key "__enc__"

  def type, do: :map

  def embed_as(_format), do: :dump

  def cast(value) when is_map(value), do: {:ok, value}
  def cast(_), do: :error

  # An empty map holds no secret. Ecto also dumps a schema's default value at
  # compile time, when no encryption key is available.
  def dump(value) when value == %{}, do: {:ok, %{}}

  def dump(value) when is_map(value) do
    {:ok, %{@key => Base.encode64(Encryption.encrypt(Jason.encode!(value), @aad))}}
  end

  def dump(_), do: :error

  def load(%{@key => encoded}) do
    with {:ok, ciphertext} <- Base.decode64(encoded),
         json when is_binary(json) <- Encryption.decrypt(ciphertext, @aad),
         {:ok, map} <- Jason.decode(json) do
      {:ok, map}
    else
      _ -> :error
    end
  end

  def load(value) when is_map(value), do: {:ok, value}
  def load(_), do: :error
end
