defmodule ZentinelCp.Services.ConsulResolver do
  @moduledoc """
  Behaviour for Consul Catalog API resolution.

  Implementations resolve Consul services into SRV-compatible tuples
  for service discovery.
  """

  @callback resolve_service(config :: map()) ::
              {:ok, [{integer(), integer(), integer(), charlist()}]}
              | {:error, term()}
end
