defmodule ZentinelCpWeb.Plugs.ClientIp do
  @moduledoc """
  Sets `conn.remote_ip` to the real client when behind trusted proxies.

  `X-Forwarded-For` can be forged by clients, who control everything before the
  entries added by your own proxies. With `TRUSTED_PROXY_COUNT=n`, this takes the
  nth entry from the right. With the default of 0 the header is ignored.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    count = Application.get_env(:zentinel_cp, :trusted_proxy_count, 0)

    with true <- count > 0,
         [header | _] <- get_req_header(conn, "x-forwarded-for"),
         entries = header |> String.split(",") |> Enum.map(&String.trim/1),
         entry when is_binary(entry) <- Enum.at(entries, -count),
         {:ok, address} <- entry |> String.to_charlist() |> :inet.parse_address() do
      %{conn | remote_ip: address}
    else
      _ -> conn
    end
  end
end
