defmodule ZentinelCpWeb.Plugs.RequireGlobalAdminKey do
  @moduledoc """
  Limits a route to API keys with no project restriction whose owner is a global
  admin, for endpoints that act on data shared by all tenants.
  """
  import Plug.Conn

  alias ZentinelCp.Access

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_api_key] do
      %{project_id: nil, user_id: user_id} = _key ->
        if Access.global_admin?(user_id), do: conn, else: forbidden(conn)

      _ ->
        forbidden(conn)
    end
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(%{error: "Requires a global admin key"}))
    |> halt()
  end
end
