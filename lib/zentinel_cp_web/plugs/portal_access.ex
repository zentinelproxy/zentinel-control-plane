defmodule ZentinelCpWeb.Plugs.PortalAccess do
  @moduledoc """
  Plug that controls access to the developer portal based on project settings.

  Checks the project's `portal_access` setting:
  - `"disabled"` → 404
  - `"public"` → allow
  - `"authenticated"` → requires a member of the project's org

  LiveViews repeat these checks in `LiveHelpers.on_mount(:portal_access)`, since
  plugs do not run when a LiveView joins over the socket.
  """

  import Plug.Conn
  alias ZentinelCp.Projects
  alias ZentinelCp.Projects.Project

  def init(opts), do: opts

  def call(conn, _opts) do
    project_slug = conn.params["project_slug"]

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> Phoenix.Controller.put_view(ZentinelCpWeb.ErrorHTML)
        |> Phoenix.Controller.render("404.html")
        |> halt()

      project ->
        case Project.portal_access(project) do
          "disabled" ->
            conn
            |> put_status(:not_found)
            |> Phoenix.Controller.put_view(ZentinelCpWeb.ErrorHTML)
            |> Phoenix.Controller.render("404.html")
            |> halt()

          "public" ->
            assign(conn, :portal_project, project)

          "authenticated" ->
            check_portal_auth(conn, project)

          _ ->
            conn
            |> put_status(:not_found)
            |> Phoenix.Controller.put_view(ZentinelCpWeb.ErrorHTML)
            |> Phoenix.Controller.render("404.html")
            |> halt()
        end
    end
  end

  # "authenticated" portals are for members of the project's org.
  defp check_portal_auth(conn, project) do
    user = conn.assigns[:current_user]

    if user && (user.role == "admin" || ZentinelCp.Orgs.get_user_role(project.org_id, user.id)) do
      assign(conn, :portal_project, project)
    else
      require_portal_login(conn)
    end
  end

  defp require_portal_login(conn) do
    conn
    |> Phoenix.Controller.redirect(to: "/login")
    |> halt()
  end
end
