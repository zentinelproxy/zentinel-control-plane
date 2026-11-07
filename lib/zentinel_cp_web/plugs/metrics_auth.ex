defmodule ZentinelCpWeb.Plugs.MetricsAuth do
  @moduledoc """
  Protects `/metrics`, which reveals fleet and tenant activity.

  Prometheus must send `Authorization: Bearer <METRICS_TOKEN>`. In production,
  without a configured token the endpoint is closed. Development and test set
  `:metrics_open` to leave it open.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    token = Application.get_env(:zentinel_cp, :metrics_token)

    cond do
      Application.get_env(:zentinel_cp, :metrics_open, false) -> conn
      is_binary(token) and authorized?(conn, token) -> conn
      true -> conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

  defp authorized?(conn, token) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> given] -> Plug.Crypto.secure_compare(given, token)
      _ -> false
    end
  end
end
