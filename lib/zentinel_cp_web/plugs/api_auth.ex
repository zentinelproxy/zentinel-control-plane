defmodule ZentinelCpWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for authenticating operators via API key.

  Expects `Authorization: Bearer <api_key>` header.
  """
  import Plug.Conn

  alias ZentinelCp.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_key} <- get_bearer_token(conn),
         %{} = api_key <- Accounts.get_api_key_by_key(raw_key) do
      Accounts.touch_api_key(api_key)

      conn
      |> assign(:current_api_key, api_key)
    else
      {:error, :missing_token} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Missing Authorization header"}))
        |> halt()

      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid or expired API key"}))
        |> halt()
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end
end
