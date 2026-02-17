defmodule ZentinelCp.Secrets.VaultClient do
  @moduledoc """
  Behaviour for HashiCorp Vault KV v2 secret engine interactions.
  """

  @callback read_secret(config :: map(), path :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback list_secrets(config :: map(), path :: String.t()) ::
              {:ok, [String.t()]} | {:error, term()}

  @callback health(config :: map()) ::
              {:ok, map()} | {:error, term()}
end
