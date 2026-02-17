defmodule ZentinelCpWeb.Plugs.OrgScope do
  @moduledoc """
  Plug that resolves the current org from the `org_slug` path parameter
  and assigns it to the connection.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias ZentinelCp.Orgs

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_params["org_slug"] || conn.params["org_slug"] do
      nil ->
        conn

      slug ->
        case Orgs.get_org_by_slug(slug) do
          nil ->
            conn
            |> put_flash(:error, "Organization not found.")
            |> redirect(to: "/orgs")
            |> halt()

          org ->
            assign(conn, :current_org, org)
        end
    end
  end
end
