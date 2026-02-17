defmodule ZentinelCp.Services.DnsResolver do
  @moduledoc """
  Behaviour for DNS SRV record resolution.

  Implementations resolve SRV records for service discovery.
  """

  @callback resolve_srv(hostname :: String.t()) ::
              {:ok, [{priority :: integer, weight :: integer, port :: integer, host :: charlist}]}
              | {:error, term()}
end
