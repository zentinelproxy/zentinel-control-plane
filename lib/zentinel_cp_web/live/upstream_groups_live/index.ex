defmodule ZentinelCpWeb.UpstreamGroupsLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        groups = Services.list_upstream_groups(project.id)

        {:ok,
         assign(socket,
           page_title: "Upstream Groups — #{project.name}",
           org: org,
           project: project,
           groups: groups
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    group = Services.get_upstream_group!(id)
    project = socket.assigns.project

    case Services.delete_upstream_group(group) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "upstream_group", group.id,
          project_id: project.id
        )

        groups = Services.list_upstream_groups(project.id)

        {:noreply,
         socket
         |> assign(groups: groups)
         |> put_flash(:info, "Upstream group deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete upstream group.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Upstream Groups</h1>
        </:filters>
        <:actions>
          <.link navigate={group_new_path(@org, @project)} class="btn btn-primary btn-sm">
            New Upstream Group
          </.link>
        </:actions>
      </.table_toolbar>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Algorithm</th>
              <th class="text-xs uppercase">Targets</th>
              <th class="text-xs uppercase">Created</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={group <- @groups}>
              <td>
                <.link
                  navigate={group_show_path(@org, @project, group)}
                  class="text-primary hover:underline font-mono"
                >
                  {group.name}
                </.link>
              </td>
              <td class="text-sm">{group.algorithm}</td>
              <td class="text-sm">{length(group.targets)}</td>
              <td class="text-sm">{Calendar.strftime(group.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="flex gap-1">
                <.link navigate={group_show_path(@org, @project, group)} class="btn btn-ghost btn-xs">
                  Details
                </.link>
                <.link navigate={group_edit_path(@org, @project, group)} class="btn btn-ghost btn-xs">
                  Edit
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={group.id}
                  data-confirm="Are you sure? Services using this group will lose their upstream reference."
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@groups == []} class="text-center py-12 text-base-content/50">
          No upstream groups yet. Create one to load balance across multiple backends.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp group_new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/new"

  defp group_new_path(nil, project),
    do: ~p"/projects/#{project.slug}/upstream-groups/new"

  defp group_show_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp group_show_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp group_edit_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}/edit"

  defp group_edit_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}/edit"
end
