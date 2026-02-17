defmodule ZentinelCpWeb.Plugs.NodeAuth do
  @moduledoc """
  Plug for authenticating Zentinel nodes.

  Supports two authentication methods:
  1. JWT Bearer token (preferred) — `Authorization: Bearer <token>`
  2. Static node key (legacy fallback) — `X-Zentinel-Node-Key: <key>`
  """
  import Plug.Conn
  alias ZentinelCp.{Auth, Nodes}

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, node} ->
        assign(conn, :current_node, node)

      {:error, reason} ->
        message = error_message(reason)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: message}))
        |> halt()
    end
  end

  defp authenticate(conn) do
    case get_bearer_token(conn) do
      {:ok, token} ->
        Auth.verify_node_token(token)

      :none ->
        case get_node_key(conn) do
          {:ok, key} -> Nodes.authenticate_node(key)
          :none -> {:error, :missing_credentials}
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, token}
      _ -> :none
    end
  end

  defp get_node_key(conn) do
    case get_req_header(conn, "x-zentinel-node-key") do
      [key | _] -> {:ok, key}
      [] -> :none
    end
  end

  defp error_message(:missing_credentials),
    do:
      "Missing authentication. Provide Authorization: Bearer <token> or X-Zentinel-Node-Key header."

  defp error_message(:invalid_key), do: "Invalid node key"
  defp error_message(:invalid_signature), do: "Invalid token signature"
  defp error_message(:token_expired), do: "Token expired"
  defp error_message(:unknown_key), do: "Unknown signing key"
  defp error_message(:key_deactivated), do: "Signing key has been deactivated"
  defp error_message(:node_not_found), do: "Node not found"
  defp error_message(_), do: "Authentication failed"
end
