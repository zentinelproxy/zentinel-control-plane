defmodule ZentinelCpWeb.PromExPlug do
  @moduledoc """
  Plug that serves Prometheus metrics from PromEx.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    prom_ex_module = Keyword.fetch!(opts, :prom_ex_module)

    metrics =
      prom_ex_module
      |> PromEx.get_metrics()
      |> IO.iodata_to_binary()

    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(200, metrics)
  end
end
