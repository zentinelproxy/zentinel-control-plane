defmodule ZentinelCpWeb.PluginsLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Plugins, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => plugin_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         plugin when not is_nil(plugin) <- Plugins.get_plugin(plugin_id),
         true <- plugin.project_id == project.id do
      versions = Plugins.list_plugin_versions(plugin.id)

      {:ok,
       assign(socket,
         page_title: "Plugin #{plugin.name} — #{project.name}",
         org: org,
         project: project,
         plugin: plugin,
         versions: versions
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    plugin = socket.assigns.plugin
    project = socket.assigns.project
    org = socket.assigns.org

    case Plugins.delete_plugin(plugin) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "plugin", plugin.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Plugin deleted.")
         |> push_navigate(to: index_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete plugin.")}
    end
  end

  @impl true
  def handle_event("delete_version", %{"id" => version_id}, socket) do
    plugin = socket.assigns.plugin
    project = socket.assigns.project

    case Plugins.get_plugin_version(version_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Version not found.")}

      version when version.plugin_id == plugin.id ->
        case Plugins.delete_plugin_version(version) do
          {:ok, _} ->
            Audit.log_user_action(
              socket.assigns.current_user,
              "delete",
              "plugin_version",
              version.id,
              project_id: project.id
            )

            versions = Plugins.list_plugin_versions(plugin.id)
            {:noreply, assign(socket, versions: versions) |> put_flash(:info, "Version deleted.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete version.")}
        end

      _version ->
        {:noreply, put_flash(socket, :error, "Version not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@plugin.name}
        resource_type="plugin"
        back_path={index_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@plugin.enabled && "badge-success") || "badge-ghost"]}>
            {if @plugin.enabled, do: "enabled", else: "disabled"}
          </span>
          <span class="badge badge-sm badge-outline">{@plugin.plugin_type}</span>
        </:badge>
        <:action>
          <.link
            navigate={edit_path(@org, @project, @plugin)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this plugin and all its versions?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@plugin.id}</span></:item>
            <:item label="Name">{@plugin.name}</:item>
            <:item label="Slug"><span class="font-mono">{@plugin.slug}</span></:item>
            <:item label="Description">{@plugin.description || "—"}</:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@plugin.plugin_type}</span>
            </:item>
            <:item label="Author">{@plugin.author || "—"}</:item>
            <:item label="Enabled">{if @plugin.enabled, do: "Yes", else: "No"}</:item>
            <:item label="Public">{if @plugin.public, do: "Yes", else: "No"}</:item>
            <:item label="Created">
              {Calendar.strftime(@plugin.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Default Configuration">
          <.definition_list>
            <:item :for={{key, value} <- Enum.sort(@plugin.default_config || %{})} label={key}>
              <span class="font-mono text-sm">{format_config_value(value)}</span>
            </:item>
          </.definition_list>
          <div
            :if={@plugin.default_config == nil || @plugin.default_config == %{}}
            class="text-center py-4 text-base-content/50 text-sm"
          >
            No default configuration set.
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Versions">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Version</th>
              <th class="text-xs">Checksum</th>
              <th class="text-xs">Size</th>
              <th class="text-xs">Uploaded</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={v <- @versions}>
              <td><span class="font-mono">{v.version}</span></td>
              <td><span class="font-mono text-xs">{String.slice(v.checksum, 0, 12)}...</span></td>
              <td>{format_file_size(v.file_size)}</td>
              <td class="text-sm">{Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td>
                <button
                  phx-click="delete_version"
                  phx-value-id={v.id}
                  data-confirm="Delete this version?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@versions == []} class="text-center py-4 text-base-content/50 text-sm">
          No versions uploaded yet. Upload a version via the API.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/plugins"

  defp edit_path(%{slug: org_slug}, project, plugin),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins/#{plugin.id}/edit"

  defp edit_path(nil, project, plugin),
    do: ~p"/projects/#{project.slug}/plugins/#{plugin.id}/edit"

  defp format_config_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_config_value(value) when is_list(value), do: inspect(value)
  defp format_config_value(value), do: to_string(value)

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
