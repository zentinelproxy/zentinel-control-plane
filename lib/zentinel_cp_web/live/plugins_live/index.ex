defmodule ZentinelCpWeb.PluginsLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Plugins, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        plugins = Plugins.list_plugins(project.id)

        {:ok,
         assign(socket,
           page_title: "Plugins — #{project.name}",
           org: org,
           project: project,
           plugins: plugins
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project
    plugin = Plugins.get_plugin!(id)

    if plugin.project_id != project.id do
      {:noreply, put_flash(socket, :error, "Plugin not found.")}
    else
      case Plugins.delete_plugin(plugin) do
        {:ok, _} ->
          Audit.log_user_action(socket.assigns.current_user, "delete", "plugin", plugin.id,
            project_id: project.id
          )

          plugins = Plugins.list_plugins(project.id)
          {:noreply, assign(socket, plugins: plugins) |> put_flash(:info, "Plugin deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete plugin.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Plugins</h1>
        <.link navigate={new_path(@org, @project)} class="btn btn-primary btn-sm">
          New Plugin
        </.link>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Type</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs">Public</th>
              <th class="text-xs">Created</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={p <- @plugins}>
              <td>
                <.link navigate={show_path(@org, @project, p)} class="link link-primary">
                  {p.name}
                </.link>
              </td>
              <td><span class="badge badge-sm badge-outline">{p.plugin_type}</span></td>
              <td>
                <span class={["badge badge-xs", (p.enabled && "badge-success") || "badge-ghost"]}>
                  {if p.enabled, do: "yes", else: "no"}
                </span>
              </td>
              <td>
                <span class={["badge badge-xs", (p.public && "badge-info") || "badge-ghost"]}>
                  {if p.public, do: "yes", else: "no"}
                </span>
              </td>
              <td class="text-sm">{Calendar.strftime(p.inserted_at, "%Y-%m-%d")}</td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={p.id}
                  data-confirm="Are you sure you want to delete this plugin?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@plugins == []} class="text-center py-8 text-base-content/50 text-sm">
          No plugins yet. Create one to extend your proxy with custom Wasm or Lua plugins.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins/new"

  defp new_path(nil, project),
    do: ~p"/projects/#{project.slug}/plugins/new"

  defp show_path(%{slug: org_slug}, project, plugin),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins/#{plugin.id}"

  defp show_path(nil, project, plugin),
    do: ~p"/projects/#{project.slug}/plugins/#{plugin.id}"
end
