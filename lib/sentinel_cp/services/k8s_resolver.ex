defmodule SentinelCp.Services.K8sResolver do
  @moduledoc """
  Behaviour for Kubernetes Endpoints API resolution.

  Implementations resolve Kubernetes endpoints into SRV-compatible tuples
  for service discovery.
  """

  @callback resolve_endpoints(config :: map()) ::
              {:ok, [{integer(), integer(), integer(), charlist()}]}
              | {:error, term()}
end
