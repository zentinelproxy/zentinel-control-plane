defmodule ZentinelCpWeb.Plugs.RateLimit do
  @moduledoc """
  Plug that enforces token bucket rate limiting on API endpoints.

  Adds standard rate limit headers to all responses:
  - `X-RateLimit-Limit` — maximum requests per window
  - `X-RateLimit-Remaining` — remaining requests in current window
  - `X-RateLimit-Reset` — Unix timestamp when the window resets
  """

  import Plug.Conn

  alias ZentinelCp.RateLimit

  def init(opts), do: opts

  def call(conn, opts) do
    key = rate_limit_key(conn)
    scope = Keyword.get(opts, :scope, "default")
    action = Keyword.get(opts, :action)

    check_opts = if action, do: [action: action], else: []

    case RateLimit.check_rate(key, scope, check_opts) do
      {:allow, remaining, limit, reset_at} ->
        conn
        |> put_rate_limit_headers(limit, remaining, reset_at)

      {:deny, limit, reset_at} ->
        conn
        |> put_rate_limit_headers(limit, 0, reset_at)
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: "rate_limit_exceeded",
            message: "Rate limit exceeded. Try again after #{reset_at}.",
            retry_after: reset_at - System.system_time(:second)
          })
        )
        |> halt()
    end
  end

  defp rate_limit_key(conn) do
    cond do
      # Prefer API key ID if authenticated
      api_key = conn.assigns[:api_key] ->
        "api_key:#{api_key.id}"

      # Fall back to IP address
      true ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        "ip:#{ip}"
    end
  end

  defp put_rate_limit_headers(conn, limit, remaining, reset_at) do
    conn
    |> put_resp_header("x-ratelimit-limit", to_string(limit))
    |> put_resp_header("x-ratelimit-remaining", to_string(max(remaining, 0)))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_at))
  end
end
