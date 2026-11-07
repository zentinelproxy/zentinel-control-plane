defmodule ZentinelCpWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for access control.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias ZentinelCp.{Accounts, Orgs, Projects}
  alias ZentinelCp.Accounts.Totp

  # Views reachable without a user. The portal is checked by `:portal_access`.
  @public_views [ZentinelCpWeb.AuthLive.Login, ZentinelCpWeb.AuthLive.Mfa]
  @public_namespaces [ZentinelCpWeb.PortalLive]

  # Portal pages that act for the viewer: the console sends requests from the
  # server, and keys creates API keys. Both need a member of the project's org.
  @portal_member_views [ZentinelCpWeb.PortalLive.Console, ZentinelCpWeb.PortalLive.Keys]

  # Events that only change what is on screen. Readers may send these and no
  # others, so a new event is write-protected until it is listed here.
  @read_only_events ~w(
    back_to_upload cancel cancel_delete cancel_discovery cancel_edit change_discovery_type
    change_type clear_selection close_generate close_preview collapse_diff compare
    confirm_delete deselect_all dismiss_key drag_enter drag_leave drop edit edit_discovery
    expand_diff filter filter_environment filter_status hide_reject_form navigate next_page
    page parse_spec prev_page preview_kdl select_all select_endpoint select_template
    select_type set_pattern set_time_range show_form show_generate show_reject_form
    switch_mode switch_route_type switch_service_type switch_strategy switch_tab
    toggle_add_member toggle_edit toggle_form toggle_fullscreen toggle_label_form
    toggle_password_form toggle_pin_form toggle_section toggle_upload toggle_view_mode
    update_body update_method update_url validate validate_config
  )

  @doc """
  on_mount hook for LiveView access control.

  Supported actions:
  - `:fetch_current_user` — assigns current user from session
  - `:enforce_access` — requires a user, and org membership on org and project
    pages. Assigns `:access_role`, and blocks changes by readers
  - `:require_admin` — requires admin role, redirects otherwise
  """
  def on_mount(action, params, session, socket)

  def on_mount(:enforce_access, params, session, socket) do
    socket = assign_current_user(socket, session)

    cond do
      public_view?(socket.view) ->
        {:cont, socket}

      is_nil(socket.assigns.current_user) ->
        {:halt, redirect(socket, to: "/login")}

      true ->
        enforce_tenant(params, socket)
    end
  end

  def on_mount(:fetch_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:portal_access, %{"project_slug" => slug}, session, socket) do
    socket = assign_current_user(socket, session)
    project = Projects.get_project_by_slug(slug)
    mode = project && ZentinelCp.Projects.Project.portal_access(project)
    member? = project && org_role?(socket.assigns, project.org_id, "reader")

    cond do
      mode not in ["public", "authenticated"] ->
        raise Ecto.NoResultsError, queryable: "portal"

      member? ->
        {:cont, assign(socket, portal_project: project, portal_member: true)}

      mode == "authenticated" or socket.view in @portal_member_views ->
        {:halt, redirect(socket, to: "/login")}

      true ->
        {:cont, assign(socket, portal_project: project, portal_member: false)}
    end
  end

  def on_mount(:attach_uri_hook, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :save_uri, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_uri, uri)}
     end)}
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user && socket.assigns.current_user.role == "admin" do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You do not have permission to access this page.")
        |> redirect(to: "/projects")

      {:halt, socket}
    end
  end

  @doc """
  Returns a record loaded from a client-supplied ID, after checking it belongs to
  the page's project. Raises otherwise, which ends the LiveView process, because
  a mismatched ID never comes from this page's own UI. Passes `nil` through.
  """
  def in_project!(nil, _socket), do: nil

  def in_project!(%{project_id: project_id} = record, %{assigns: %{project: %{id: project_id}}}) do
    record
  end

  def in_project!(_record, _socket) do
    raise Ecto.NoResultsError, queryable: "record in this project"
  end

  @doc "As `in_project!/2`, for a project whose org must match the page's org."
  def in_org!(%{org_id: org_id} = project, %{assigns: %{org: %{id: org_id}}}), do: project

  def in_org!(_project, _socket) do
    raise Ecto.NoResultsError, queryable: "project in this org"
  end

  @doc "Keeps the rollouts in orgs the user belongs to. Rollouts must preload `:project`."
  def visible_to_user(rollouts, %{assigns: %{current_user: %{role: "admin"}}}), do: rollouts

  def visible_to_user(rollouts, %{assigns: %{current_user: user}}) do
    org_ids = user.id |> Orgs.list_user_orgs() |> Enum.map(fn {org, _role} -> org.id end)
    Enum.filter(rollouts, &(&1.project.org_id in org_ids))
  end

  @doc "Returns true if a global admin or a member of the org with at least `role`."
  def org_role?(%{assigns: assigns}, org_id, role), do: org_role?(assigns, org_id, role)
  def org_role?(%{current_user: %{role: "admin"}}, _org_id, _role), do: true

  def org_role?(%{current_user: %{id: user_id}}, org_id, role) do
    Orgs.user_has_role?(org_id, user_id, role)
  end

  def org_role?(_assigns, _org_id, _role), do: false

  defp public_view?(view) do
    view in @public_views or
      Enum.any?(@public_namespaces, fn namespace ->
        String.starts_with?(Atom.to_string(view), Atom.to_string(namespace) <> ".")
      end)
  end

  defp enforce_tenant(params, socket) do
    case tenant_org_id(params) do
      :none -> {:cont, assign(socket, :access_role, nil)}
      :mismatch -> deny(socket)
      org_id -> enforce_membership(org_id, socket)
    end
  end

  # Unknown slugs fall through so the view can show its own not-found page.
  defp tenant_org_id(%{"project_slug" => project_slug} = params) do
    project = Projects.get_project_by_slug(project_slug)
    org = params["org_slug"] && Orgs.get_org_by_slug(params["org_slug"])

    cond do
      is_nil(project) -> :none
      org && org.id != project.org_id -> :mismatch
      true -> project.org_id
    end
  end

  defp tenant_org_id(%{"org_slug" => org_slug}) do
    case Orgs.get_org_by_slug(org_slug) do
      nil -> :none
      org -> org.id
    end
  end

  defp tenant_org_id(_params), do: :none

  defp enforce_membership(org_id, socket) do
    user = socket.assigns.current_user

    case user.role == "admin" || Orgs.get_user_role(org_id, user.id) do
      true ->
        enforce_mfa_policy(org_id, assign(socket, :access_role, "admin"))

      nil ->
        deny(socket)

      false ->
        deny(socket)

      "reader" ->
        enforce_mfa_policy(org_id, socket |> assign(:access_role, "reader") |> block_writes())

      role ->
        enforce_mfa_policy(org_id, assign(socket, :access_role, role))
    end
  end

  defp enforce_mfa_policy(org_id, socket) do
    if Totp.blocked_by_policy?(socket.assigns.current_user, Orgs.get_org(org_id)) do
      socket =
        socket
        |> put_flash(:error, "This organization requires two-factor authentication.")
        |> redirect(to: "/profile")

      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  defp block_writes(socket) do
    attach_hook(socket, :block_reader_writes, :handle_event, fn event, _params, socket ->
      if event in @read_only_events do
        {:cont, socket}
      else
        {:halt, put_flash(socket, :error, "Your role does not allow this action.")}
      end
    end)
  end

  defp deny(socket) do
    socket =
      socket
      |> put_flash(:error, "You do not have permission to access this page.")
      |> redirect(to: "/orgs")

    {:halt, socket}
  end

  defp assign_current_user(socket, session) do
    case session["user_token"] do
      nil ->
        assign(socket, :current_user, nil)

      token ->
        user = Accounts.get_user_by_session_token(token)
        assign(socket, :current_user, user)
    end
  end
end
