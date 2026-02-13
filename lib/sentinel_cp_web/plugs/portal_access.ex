defmodule SentinelCpWeb.Plugs.PortalAccess do
  @moduledoc """
  Plug that controls access to the developer portal based on project settings.

  Checks the project's `portal_access` setting:
  - `"disabled"` → 404
  - `"public"` → allow
  - `"authenticated"` → check session for portal user or API key
  """

  import Plug.Conn
  alias SentinelCp.Projects
  alias SentinelCp.Projects.Project

  def init(opts), do: opts

  def call(conn, _opts) do
    project_slug = conn.params["project_slug"]

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> Phoenix.Controller.put_view(SentinelCpWeb.ErrorHTML)
        |> Phoenix.Controller.render("404.html")
        |> halt()

      project ->
        case Project.portal_access(project) do
          "disabled" ->
            conn
            |> put_status(:not_found)
            |> Phoenix.Controller.put_view(SentinelCpWeb.ErrorHTML)
            |> Phoenix.Controller.render("404.html")
            |> halt()

          "public" ->
            assign(conn, :portal_project, project)

          "authenticated" ->
            check_portal_auth(conn, project)

          _ ->
            conn
            |> put_status(:not_found)
            |> Phoenix.Controller.put_view(SentinelCpWeb.ErrorHTML)
            |> Phoenix.Controller.render("404.html")
            |> halt()
        end
    end
  end

  defp check_portal_auth(conn, project) do
    portal_user = get_session(conn, :portal_user)

    if portal_user do
      conn
      |> assign(:portal_project, project)
      |> assign(:portal_user, portal_user)
    else
      # Check for API key in Authorization header
      case get_req_header(conn, "authorization") do
        ["Bearer " <> key] ->
          case SentinelCp.Accounts.get_api_key_by_key(key) do
            nil ->
              require_portal_login(conn)

            api_key ->
              conn
              |> assign(:portal_project, project)
              |> assign(:portal_api_key, api_key)
          end

        _ ->
          require_portal_login(conn)
      end
    end
  end

  defp require_portal_login(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.put_view(SentinelCpWeb.ErrorHTML)
    |> Phoenix.Controller.render("401.html")
    |> halt()
  end
end
