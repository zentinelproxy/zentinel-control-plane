defmodule SentinelCpWeb.UpstreamGroupsLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => group_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         group when not is_nil(group) <- Services.get_upstream_group(group_id),
         true <- group.project_id == project.id do
      discovery_source = Services.get_discovery_source_for_group(group.id)

      if connected?(socket) && discovery_source do
        Phoenix.PubSub.subscribe(SentinelCp.PubSub, "discovery:#{discovery_source.id}")
      end

      {:ok,
       assign(socket,
         page_title: "Upstream Group #{group.name} — #{project.name}",
         org: org,
         project: project,
         group: group,
         discovery_source: discovery_source,
         show_discovery_form: false,
         editing_discovery: false
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_info({:discovery_synced, _source_id}, socket) do
    group = Services.get_upstream_group!(socket.assigns.group.id)
    discovery_source = Services.get_discovery_source_for_group(group.id)

    {:noreply, assign(socket, group: group, discovery_source: discovery_source)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    group = socket.assigns.group
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_upstream_group(group) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "upstream_group", group.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Upstream group deleted.")
         |> push_navigate(to: groups_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete upstream group.")}
    end
  end

  @impl true
  def handle_event("add_target", params, socket) do
    group = socket.assigns.group

    attrs = %{
      upstream_group_id: group.id,
      host: params["host"],
      port: parse_int(params["port"]),
      weight: parse_int(params["weight"]) || 100
    }

    case Services.add_upstream_target(attrs) do
      {:ok, _target} ->
        group = Services.get_upstream_group!(group.id)
        {:noreply, assign(socket, group: group) |> put_flash(:info, "Target added.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  @impl true
  def handle_event("remove_target", %{"id" => target_id}, socket) do
    target = Services.get_upstream_target(target_id)

    if target do
      Services.remove_upstream_target(target)
      group = Services.get_upstream_group!(socket.assigns.group.id)
      {:noreply, assign(socket, group: group) |> put_flash(:info, "Target removed.")}
    else
      {:noreply, put_flash(socket, :error, "Target not found.")}
    end
  end

  # Discovery events

  def handle_event("enable_discovery", _, socket) do
    {:noreply, assign(socket, show_discovery_form: true)}
  end

  def handle_event("cancel_discovery", _, socket) do
    {:noreply, assign(socket, show_discovery_form: false, editing_discovery: false)}
  end

  def handle_event("create_discovery", params, socket) do
    group = socket.assigns.group
    project = socket.assigns.project

    attrs = %{
      hostname: params["hostname"],
      sync_interval_seconds: parse_int(params["sync_interval_seconds"]) || 60,
      auto_sync: params["auto_sync"] == "true",
      upstream_group_id: group.id,
      project_id: project.id
    }

    case Services.create_discovery_source(attrs) do
      {:ok, source} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "discovery:#{source.id}")
        end

        {:noreply,
         socket
         |> assign(discovery_source: source, show_discovery_form: false)
         |> put_flash(:info, "Discovery source created.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  def handle_event("edit_discovery", _, socket) do
    {:noreply, assign(socket, editing_discovery: true)}
  end

  def handle_event("update_discovery", params, socket) do
    source = socket.assigns.discovery_source

    attrs = %{
      hostname: params["hostname"],
      sync_interval_seconds: parse_int(params["sync_interval_seconds"]) || 60,
      auto_sync: params["auto_sync"] == "true"
    }

    case Services.update_discovery_source(source, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(discovery_source: updated, editing_discovery: false)
         |> put_flash(:info, "Discovery source updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  def handle_event("sync_now", _, socket) do
    source = socket.assigns.discovery_source

    case Services.sync_discovery_source(source) do
      {:ok, result} ->
        group = Services.get_upstream_group!(socket.assigns.group.id)
        updated_source = Services.get_discovery_source!(source.id)

        {:noreply,
         socket
         |> assign(group: group, discovery_source: updated_source)
         |> put_flash(
           :info,
           "Sync complete: #{result.added} added, #{result.removed} removed, #{result.kept} kept."
         )}

      {:error, reason} ->
        updated_source = Services.get_discovery_source!(source.id)

        {:noreply,
         socket
         |> assign(discovery_source: updated_source)
         |> put_flash(:error, "Sync failed: #{reason}")}
    end
  end

  def handle_event("toggle_auto_sync", _, socket) do
    source = socket.assigns.discovery_source

    case Services.update_discovery_source(source, %{auto_sync: !source.auto_sync}) do
      {:ok, updated} ->
        msg = if updated.auto_sync, do: "Auto-sync enabled.", else: "Auto-sync disabled."
        {:noreply, assign(socket, discovery_source: updated) |> put_flash(:info, msg)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not toggle auto-sync.")}
    end
  end

  def handle_event("delete_discovery", _, socket) do
    source = socket.assigns.discovery_source

    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(SentinelCp.PubSub, "discovery:#{source.id}")
    end

    case Services.delete_discovery_source(source) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(discovery_source: nil, show_discovery_form: false)
         |> put_flash(:info, "Discovery source removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove discovery source.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@group.name}
        resource_type="upstream group"
        back_path={groups_path(@org, @project)}
      >
        <:action>
          <.link
            navigate={group_edit_path(@org, @project, @group)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this upstream group?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Configuration">
          <.definition_list>
            <:item label="Name">{@group.name}</:item>
            <:item label="Slug"><span class="font-mono">{@group.slug}</span></:item>
            <:item label="Algorithm">{@group.algorithm}</:item>
            <:item label="Description">{@group.description || "—"}</:item>
            <:item label="Health Check">{format_map(@group.health_check)}</:item>
            <:item label="Circuit Breaker">{format_map(@group.circuit_breaker)}</:item>
            <:item label="Sticky Sessions">{format_map(@group.sticky_sessions)}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Service Discovery">
          <%= cond do %>
            <% @editing_discovery && @discovery_source -> %>
              <form phx-submit="update_discovery" class="space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text text-xs">Hostname</span></label>
                  <input
                    type="text"
                    name="hostname"
                    required
                    class="input input-bordered input-sm"
                    value={@discovery_source.hostname}
                    placeholder="_http._tcp.api.internal"
                  />
                </div>
                <div class="flex gap-2">
                  <div class="form-control">
                    <label class="label"><span class="label-text text-xs">Interval (seconds)</span></label>
                    <input
                      type="number"
                      name="sync_interval_seconds"
                      class="input input-bordered input-sm w-24"
                      value={@discovery_source.sync_interval_seconds}
                      min="10"
                    />
                  </div>
                  <div class="form-control">
                    <label class="label cursor-pointer gap-2">
                      <span class="label-text text-xs">Auto-sync</span>
                      <input
                        type="checkbox"
                        name="auto_sync"
                        value="true"
                        checked={@discovery_source.auto_sync}
                        class="checkbox checkbox-sm"
                      />
                    </label>
                  </div>
                </div>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Save</button>
                  <button type="button" phx-click="cancel_discovery" class="btn btn-ghost btn-sm">Cancel</button>
                </div>
              </form>

            <% @discovery_source -> %>
              <.definition_list>
                <:item label="Type">{@discovery_source.source_type}</:item>
                <:item label="Hostname"><span class="font-mono text-sm">{@discovery_source.hostname}</span></:item>
                <:item label="Status">
                  <span class={["badge badge-sm", sync_status_class(@discovery_source.last_sync_status)]}>
                    {sync_status_label(@discovery_source.last_sync_status)}
                  </span>
                </:item>
                <:item label="Targets">{@discovery_source.last_sync_targets_count}</:item>
                <:item label="Last sync">{format_sync_time(@discovery_source.last_synced_at)}</:item>
                <:item label="Auto-sync">
                  <label class="cursor-pointer flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={@discovery_source.auto_sync}
                      phx-click="toggle_auto_sync"
                      class="toggle toggle-xs"
                    />
                    <span class="text-xs">{if @discovery_source.auto_sync, do: "on", else: "off"}</span>
                  </label>
                </:item>
                <:item label="Interval">{@discovery_source.sync_interval_seconds}s</:item>
              </.definition_list>

              <div :if={@discovery_source.last_sync_status == "error" && @discovery_source.last_sync_error} class="mt-2 text-xs text-error">
                Error: {@discovery_source.last_sync_error}
              </div>

              <div class="flex gap-2 mt-4 pt-3 border-t border-base-300">
                <button phx-click="sync_now" class="btn btn-outline btn-xs">Refresh Now</button>
                <button phx-click="edit_discovery" class="btn btn-ghost btn-xs">Edit</button>
                <button
                  phx-click="delete_discovery"
                  data-confirm="Remove discovery source? Existing targets will be kept."
                  class="btn btn-ghost btn-xs text-error"
                >
                  Remove
                </button>
              </div>

            <% @show_discovery_form -> %>
              <form phx-submit="create_discovery" class="space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text text-xs">Hostname</span></label>
                  <input
                    type="text"
                    name="hostname"
                    required
                    class="input input-bordered input-sm"
                    placeholder="_http._tcp.api.internal"
                  />
                </div>
                <div class="flex gap-2">
                  <div class="form-control">
                    <label class="label"><span class="label-text text-xs">Interval (seconds)</span></label>
                    <input
                      type="number"
                      name="sync_interval_seconds"
                      class="input input-bordered input-sm w-24"
                      value="60"
                      min="10"
                    />
                  </div>
                  <div class="form-control">
                    <label class="label cursor-pointer gap-2">
                      <span class="label-text text-xs">Auto-sync</span>
                      <input
                        type="checkbox"
                        name="auto_sync"
                        value="true"
                        checked
                        class="checkbox checkbox-sm"
                      />
                    </label>
                  </div>
                </div>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Create</button>
                  <button type="button" phx-click="cancel_discovery" class="btn btn-ghost btn-sm">Cancel</button>
                </div>
              </form>

            <% true -> %>
              <div class="text-center py-4">
                <p class="text-base-content/50 text-sm mb-3">No discovery source configured.</p>
                <button phx-click="enable_discovery" class="btn btn-outline btn-sm">
                  Enable DNS Discovery
                </button>
              </div>
          <% end %>
        </.k8s_section>
      </div>

      <.k8s_section title="Targets">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Host</th>
              <th class="text-xs">Port</th>
              <th class="text-xs">Weight</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={target <- @group.targets}>
              <td class="font-mono text-sm">{target.host}</td>
              <td class="text-sm">{target.port}</td>
              <td class="text-sm">{target.weight}</td>
              <td>
                <span class={["badge badge-xs", (target.enabled && "badge-success") || "badge-ghost"]}>
                  {if target.enabled, do: "yes", else: "no"}
                </span>
              </td>
              <td>
                <button
                  phx-click="remove_target"
                  phx-value-id={target.id}
                  data-confirm="Remove this target?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@group.targets == []} class="text-center py-4 text-base-content/50 text-sm">
          No targets yet.
        </div>

        <form phx-submit="add_target" class="flex items-end gap-2 mt-4 pt-4 border-t border-base-300">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Host</span></label>
            <input type="text" name="host" required class="input input-bordered input-xs w-40" placeholder="api.internal" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Port</span></label>
            <input type="number" name="port" required class="input input-bordered input-xs w-20" placeholder="8080" min="1" max="65535" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Weight</span></label>
            <input type="number" name="weight" class="input input-bordered input-xs w-20" placeholder="100" min="1" />
          </div>
          <button type="submit" class="btn btn-outline btn-xs">Add Target</button>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp groups_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups"

  defp groups_path(nil, project),
    do: ~p"/projects/#{project.slug}/upstream-groups"

  defp group_edit_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}/edit"

  defp group_edit_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}/edit"

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n

  defp format_map(nil), do: "—"
  defp format_map(map) when map == %{}, do: "—"
  defp format_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp sync_status_class("synced"), do: "badge-success"
  defp sync_status_class("syncing"), do: "badge-info"
  defp sync_status_class("error"), do: "badge-error"
  defp sync_status_class(_), do: "badge-ghost"

  defp sync_status_label("synced"), do: "Synced"
  defp sync_status_label("syncing"), do: "Syncing..."
  defp sync_status_label("error"), do: "Error"
  defp sync_status_label("pending"), do: "Pending"
  defp sync_status_label(status), do: status

  defp format_sync_time(nil), do: "Never"
  defp format_sync_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end
end
