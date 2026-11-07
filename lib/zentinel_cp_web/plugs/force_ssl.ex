defmodule ZentinelCpWeb.Plugs.ForceSsl do
  @moduledoc """
  Redirects HTTP to HTTPS and sets HSTS when `FORCE_SSL` is enabled.

  Phoenix's `:force_ssl` option is read at compile time, so it cannot be set on a
  published image. This reads the setting at runtime. Health checks are exempt
  because load balancers call them over plain HTTP.
  """

  @exempt_paths ["/health", "/ready"]

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: path} = conn, _opts) when path in @exempt_paths, do: conn

  def call(conn, _opts) do
    if Application.get_env(:zentinel_cp, :force_ssl, false) do
      Plug.SSL.call(conn, Plug.SSL.init(rewrite_on: [:x_forwarded_proto]))
    else
      conn
    end
  end
end
