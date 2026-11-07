defmodule ZentinelCpWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a Content-Security-Policy header with a per-request nonce for the one
  inline script in the root layout.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    policy =
      Enum.join(
        [
          "default-src 'self'",
          "script-src 'self' 'nonce-#{nonce}'",
          # LiveView and the component library set inline styles.
          "style-src 'self' 'unsafe-inline'",
          "img-src 'self' data:",
          "font-src 'self' data:",
          "connect-src 'self' ws: wss:",
          "frame-ancestors 'none'",
          "base-uri 'self'",
          "form-action 'self'",
          "object-src 'none'"
        ],
        "; "
      )

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
  end
end
