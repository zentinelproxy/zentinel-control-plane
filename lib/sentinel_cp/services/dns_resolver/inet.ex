defmodule SentinelCp.Services.DnsResolver.Inet do
  @moduledoc """
  DNS SRV resolver using Erlang's `:inet_res` module.
  """

  @behaviour SentinelCp.Services.DnsResolver

  @impl true
  def resolve_srv(hostname) do
    records = :inet_res.lookup(to_charlist(hostname), :in, :srv)
    {:ok, records}
  rescue
    e -> {:error, Exception.message(e)}
  end
end
