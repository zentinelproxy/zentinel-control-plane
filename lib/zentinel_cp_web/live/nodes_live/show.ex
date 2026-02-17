defmodule ZentinelCpWeb.NodesLive.Show do
  @moduledoc """
  LiveView for viewing node details.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Bundles, Nodes, Orgs, Projects}
  alias ZentinelCp.Nodes.Node

  @impl true
  def mount(%{"project_slug" => project_slug, "id" => node_id} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Project not found") |> redirect(to: ~p"/")}

      project ->
        case Nodes.get_node(node_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Node not found")
             |> redirect(to: nodes_path(org, project))}

          %{project_id: pid} = node when pid == project.id ->
            if connected?(socket) do
              Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "nodes:#{project.id}:#{node.id}")
              Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "node:#{node.id}:drift")
              :timer.send_interval(10_000, self(), :refresh)
            end

            heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)
            events = Nodes.list_node_events(node.id)
            runtime_config = Nodes.get_runtime_config(node.id)
            drift_events = Nodes.list_node_drift_events(node.id)
            compiled_bundles = Bundles.list_bundles(project.id, status: "compiled")

            {:ok,
             socket
             |> assign(:org, org)
             |> assign(:project, project)
             |> assign(:node, node)
             |> assign(:heartbeats, heartbeats)
             |> assign(:events, events)
             |> assign(:runtime_config, runtime_config)
             |> assign(:drift_events, drift_events)
             |> assign(:compiled_bundles, compiled_bundles)
             |> assign(:active_tab, "events")
             |> assign(:show_label_form, false)
             |> assign(:show_pin_form, false)
             |> assign(:page_title, "#{node.name} - #{project.name}")}

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Node not found")
             |> redirect(to: nodes_path(org, project))}
        end
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp nodes_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp nodes_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp bundle_path(%{slug: org_slug}, project, bundle_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle_id}"

  defp bundle_path(nil, project, bundle_id),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle_id}"

  @impl true
  def handle_info(:refresh, socket) do
    node = Nodes.get_node!(socket.assigns.node.id)
    heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)
    events = Nodes.list_node_events(node.id)
    runtime_config = Nodes.get_runtime_config(node.id)
    drift_events = Nodes.list_node_drift_events(node.id)

    {:noreply,
     assign(socket,
       node: node,
       heartbeats: heartbeats,
       events: events,
       runtime_config: runtime_config,
       drift_events: drift_events
     )}
  end

  @impl true
  def handle_info({:node_updated, node}, socket) do
    heartbeats = Nodes.list_recent_heartbeats(node.id, limit: 20)
    events = Nodes.list_node_events(node.id)
    runtime_config = Nodes.get_runtime_config(node.id)
    drift_events = Nodes.list_node_drift_events(node.id)

    {:noreply,
     assign(socket,
       node: node,
       heartbeats: heartbeats,
       events: events,
       runtime_config: runtime_config,
       drift_events: drift_events
     )}
  end

  @impl true
  def handle_info({:drift_event, _type, _event_id}, socket) do
    drift_events = Nodes.list_node_drift_events(socket.assigns.node.id)
    {:noreply, assign(socket, drift_events: drift_events)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    case Nodes.delete_node(socket.assigns.node) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "delete",
          "node",
          socket.assigns.node.id,
          project_id: socket.assigns.project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Node deleted")
         |> redirect(to: nodes_path(socket.assigns.org, socket.assigns.project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete node")}
    end
  end

  def handle_event("toggle_label_form", _, socket) do
    {:noreply, assign(socket, show_label_form: !socket.assigns.show_label_form)}
  end

  def handle_event("update_labels", %{"labels" => labels_str}, socket) do
    labels =
      labels_str
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    node = socket.assigns.node

    case Nodes.update_node_labels(node, labels) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update_labels", "node", node.id,
          project_id: socket.assigns.project.id
        )

        {:noreply,
         socket
         |> assign(node: updated, show_label_form: false)
         |> put_flash(:info, "Labels updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update labels.")}
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("toggle_pin_form", _, socket) do
    {:noreply, assign(socket, show_pin_form: !socket.assigns.show_pin_form)}
  end

  def handle_event("pin_to_bundle", %{"bundle_id" => bundle_id}, socket) do
    node = socket.assigns.node

    case Nodes.pin_node_to_bundle(node.id, bundle_id) do
      {:ok, updated_node} ->
        Audit.log_user_action(socket.assigns.current_user, "pin_bundle", "node", node.id,
          project_id: socket.assigns.project.id,
          metadata: %{bundle_id: bundle_id}
        )

        {:noreply,
         socket
         |> assign(node: updated_node, show_pin_form: false)
         |> put_flash(:info, "Node pinned to bundle.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not pin node to bundle.")}
    end
  end

  def handle_event("unpin_bundle", _, socket) do
    node = socket.assigns.node

    case Nodes.unpin_node(node.id) do
      {:ok, updated_node} ->
        Audit.log_user_action(socket.assigns.current_user, "unpin_bundle", "node", node.id,
          project_id: socket.assigns.project.id
        )

        {:noreply,
         socket
         |> assign(node: updated_node)
         |> put_flash(:info, "Node unpinned from bundle.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unpin node.")}
    end
  end

  def handle_event("set_version_constraints", params, socket) do
    node = socket.assigns.node

    opts = [
      min_bundle_version: empty_to_nil(params["min_bundle_version"]),
      max_bundle_version: empty_to_nil(params["max_bundle_version"])
    ]

    case Nodes.set_node_version_constraints(node.id, opts) do
      {:ok, updated_node} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "set_version_constraints",
          "node",
          node.id,
          project_id: socket.assigns.project.id,
          metadata: %{
            min_bundle_version: opts[:min_bundle_version],
            max_bundle_version: opts[:max_bundle_version]
          }
        )

        {:noreply,
         socket
         |> assign(node: updated_node, show_pin_form: false)
         |> put_flash(:info, "Version constraints updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update version constraints.")}
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(str), do: str

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header name={@node.name} resource_type="node" back_path={nodes_path(@org, @project)}>
        <:badge>
          <.status_badge status={@node.status} />
          <span :if={@node.version} class="badge badge-outline badge-sm font-mono">
            v{@node.version}
          </span>
        </:badge>
        <:subtitle>Registered {format_datetime(@node.registered_at)}</:subtitle>
        <:action>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this node?"
            class="btn btn-error btn-sm"
          >
            Delete Node
          </button>
        </:action>
      </.detail_header>

      <.drift_alert :if={node_drifted?(@node)} node={@node} org={@org} project={@project} />

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Node Information">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@node.id}</span></:item>
            <:item label="Hostname">
              <span class="font-mono text-sm">{@node.hostname || "-"}</span>
            </:item>
            <:item label="IP Address"><span class="font-mono text-sm">{@node.ip || "-"}</span></:item>
            <:item label="Version">
              <span class="font-mono text-sm">{@node.version || "-"}</span>
            </:item>
            <:item label="Last Seen">
              {if @node.last_seen_at, do: format_relative_time(@node.last_seen_at), else: "Never"}
            </:item>
            <:item label="Active Bundle">
              <%= if @node.active_bundle_id do %>
                <.link
                  navigate={bundle_path(@org, @project, @node.active_bundle_id)}
                  class="link link-primary font-mono text-sm"
                >
                  {String.slice(@node.active_bundle_id, 0, 8)}…
                </.link>
              <% else %>
                <span class="text-base-content/50">None</span>
              <% end %>
            </:item>
            <:item label="Staged Bundle">
              <%= if @node.staged_bundle_id do %>
                <.link
                  navigate={bundle_path(@org, @project, @node.staged_bundle_id)}
                  class="link link-primary font-mono text-sm"
                >
                  {String.slice(@node.staged_bundle_id, 0, 8)}…
                </.link>
              <% else %>
                <span class="text-base-content/50">None</span>
              <% end %>
            </:item>
            <:item label="Expected Bundle">
              <%= if @node.expected_bundle_id do %>
                <.link
                  navigate={bundle_path(@org, @project, @node.expected_bundle_id)}
                  class="link link-primary font-mono text-sm"
                >
                  {String.slice(@node.expected_bundle_id, 0, 8)}…
                </.link>
              <% else %>
                <span class="text-base-content/50">Unmanaged</span>
              <% end %>
            </:item>
          </.definition_list>
        </.k8s_section>

        <div class="space-y-4">
          <.k8s_section title="Labels">
            <div class="flex justify-end mb-2">
              <button class="btn btn-ghost btn-xs" phx-click="toggle_label_form">Edit Labels</button>
            </div>
            <div :if={@show_label_form} class="mb-3">
              <form phx-submit="update_labels" class="space-y-3">
                <textarea
                  name="labels"
                  rows="5"
                  class="textarea textarea-bordered textarea-sm font-mono text-sm w-full"
                >{format_labels_for_edit(@node.labels)}</textarea>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-xs">Save</button>
                  <button type="button" class="btn btn-ghost btn-xs" phx-click="toggle_label_form">
                    Cancel
                  </button>
                </div>
              </form>
            </div>
            <%= if @node.labels && map_size(@node.labels) > 0 do %>
              <div class="flex flex-wrap gap-2" data-testid="node-labels">
                <%= for {key, value} <- @node.labels do %>
                  <span class="badge badge-outline badge-sm">{key}: {value}</span>
                <% end %>
              </div>
            <% else %>
              <p class="text-base-content/50 text-sm" data-testid="node-labels">No labels</p>
            <% end %>
          </.k8s_section>

          <.k8s_section title="Capabilities">
            <%= if @node.capabilities && length(@node.capabilities) > 0 do %>
              <div class="flex flex-wrap gap-2">
                <%= for cap <- @node.capabilities do %>
                  <span class="badge badge-primary badge-outline badge-sm">{cap}</span>
                <% end %>
              </div>
            <% else %>
              <p class="text-base-content/50 text-sm">No capabilities reported</p>
            <% end %>
          </.k8s_section>

          <.k8s_section title="Version Pinning">
            <div class="flex justify-end mb-2">
              <button class="btn btn-ghost btn-xs" phx-click="toggle_pin_form">
                {if @show_pin_form, do: "Hide", else: "Configure"}
              </button>
            </div>

            <div class="space-y-2 text-sm">
              <div class="flex justify-between">
                <span class="text-base-content/70">Pinned Bundle:</span>
                <%= if @node.pinned_bundle_id do %>
                  <div class="flex items-center gap-2">
                    <.link
                      navigate={bundle_path(@org, @project, @node.pinned_bundle_id)}
                      class="font-mono text-primary hover:underline"
                    >
                      {String.slice(@node.pinned_bundle_id, 0, 8)}…
                    </.link>
                    <button phx-click="unpin_bundle" class="btn btn-ghost btn-xs text-error">
                      Unpin
                    </button>
                  </div>
                <% else %>
                  <span class="text-base-content/50">None</span>
                <% end %>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/70">Min Version:</span>
                <span class="font-mono">{@node.min_bundle_version || "—"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-base-content/70">Max Version:</span>
                <span class="font-mono">{@node.max_bundle_version || "—"}</span>
              </div>
            </div>

            <div :if={@show_pin_form} class="mt-4 pt-4 border-t border-base-300 space-y-4">
              <form phx-submit="pin_to_bundle" class="form-control">
                <label class="label"><span class="label-text">Pin to Bundle</span></label>
                <div class="flex gap-2">
                  <select name="bundle_id" required class="select select-bordered select-sm flex-1">
                    <option value="">Select a bundle</option>
                    <option :for={bundle <- @compiled_bundles} value={bundle.id}>
                      {bundle.version}
                    </option>
                  </select>
                  <button type="submit" class="btn btn-primary btn-sm">
                    Pin
                  </button>
                </div>
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Pinned nodes won't be updated by rollouts.
                  </span>
                </label>
              </form>

              <div class="divider text-xs">OR Set Version Constraints</div>

              <form phx-submit="set_version_constraints" class="space-y-3">
                <div class="grid grid-cols-2 gap-2">
                  <div class="form-control">
                    <label class="label"><span class="label-text text-xs">Min Version</span></label>
                    <input
                      type="text"
                      name="min_bundle_version"
                      value={@node.min_bundle_version}
                      class="input input-bordered input-sm font-mono"
                      placeholder="e.g. 1.0.0"
                    />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text text-xs">Max Version</span></label>
                    <input
                      type="text"
                      name="max_bundle_version"
                      value={@node.max_bundle_version}
                      class="input input-bordered input-sm font-mono"
                      placeholder="e.g. 2.0.0"
                    />
                  </div>
                </div>
                <button type="submit" class="btn btn-sm btn-outline w-full">
                  Update Constraints
                </button>
              </form>
            </div>
          </.k8s_section>
        </div>
      </div>

      <%!-- Tabbed Section --%>
      <.k8s_section>
        <div class="border-b border-base-300 mb-4">
          <div class="flex -mb-px">
            <button
              phx-click="switch_tab"
              phx-value-tab="events"
              class={"px-4 py-2 text-sm font-medium border-b-2 #{if @active_tab == "events", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content"}"}
            >
              Events
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="config"
              class={"px-4 py-2 text-sm font-medium border-b-2 #{if @active_tab == "config", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content"}"}
            >
              Runtime Config
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="heartbeats"
              class={"px-4 py-2 text-sm font-medium border-b-2 #{if @active_tab == "heartbeats", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content"}"}
            >
              Heartbeats
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="drift"
              class={"px-4 py-2 text-sm font-medium border-b-2 #{if @active_tab == "drift", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content"}"}
            >
              Drift History
              <span :if={has_active_drift?(@drift_events)} class="ml-1 badge badge-warning badge-xs">
                !
              </span>
            </button>
          </div>
        </div>

        <div :if={@active_tab == "events"}>
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Time</th>
                <th class="text-xs uppercase">Type</th>
                <th class="text-xs uppercase">Severity</th>
                <th class="text-xs uppercase">Message</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr>
                  <td class="text-sm">{format_datetime(event.inserted_at)}</td>
                  <td><span class="badge badge-outline badge-sm">{event.event_type}</span></td>
                  <td><.severity_badge severity={event.severity} /></td>
                  <td class="text-sm">{event.message}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div :if={Enum.empty?(@events)} class="p-8 text-center text-base-content/50">
            No events recorded yet.
          </div>
        </div>

        <div :if={@active_tab == "config"}>
          <%= if @runtime_config do %>
            <div class="mb-3 flex items-center gap-4 text-sm text-base-content/50">
              <span>Last updated: {format_datetime(@runtime_config.updated_at)}</span>
              <span class="font-mono">Hash: {String.slice(@runtime_config.config_hash, 0, 12)}…</span>
            </div>
            <pre class="bg-base-300 rounded p-4 overflow-x-auto text-sm font-mono">{@runtime_config.config_kdl}</pre>
          <% else %>
            <div class="p-8 text-center text-base-content/50">
              No runtime config reported yet.
            </div>
          <% end %>
        </div>

        <div :if={@active_tab == "heartbeats"}>
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Timestamp</th>
                <th class="text-xs uppercase">Health Status</th>
                <th class="text-xs uppercase">Active Bundle</th>
                <th class="text-xs uppercase">Staged Bundle</th>
              </tr>
            </thead>
            <tbody>
              <%= for hb <- @heartbeats do %>
                <tr>
                  <td class="text-sm">{format_datetime(hb.inserted_at)}</td>
                  <td><.health_badge health={hb.health} /></td>
                  <td class="font-mono text-sm">{hb.active_bundle_id || "-"}</td>
                  <td class="font-mono text-sm">{hb.staged_bundle_id || "-"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div :if={Enum.empty?(@heartbeats)} class="p-8 text-center text-base-content/50">
            No heartbeats recorded yet.
          </div>
        </div>

        <div :if={@active_tab == "drift"}>
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Detected</th>
                <th class="text-xs uppercase">Expected Bundle</th>
                <th class="text-xs uppercase">Actual Bundle</th>
                <th class="text-xs uppercase">Status</th>
                <th class="text-xs uppercase">Resolution</th>
                <th class="text-xs uppercase">Resolved At</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @drift_events do %>
                <tr>
                  <td class="text-sm">{format_datetime(event.detected_at)}</td>
                  <td>
                    <.link
                      navigate={bundle_path(@org, @project, event.expected_bundle_id)}
                      class="font-mono text-sm text-primary hover:underline"
                    >
                      {String.slice(event.expected_bundle_id, 0, 8)}
                    </.link>
                  </td>
                  <td>
                    <%= if event.actual_bundle_id do %>
                      <.link
                        navigate={bundle_path(@org, @project, event.actual_bundle_id)}
                        class="font-mono text-sm text-primary hover:underline"
                      >
                        {String.slice(event.actual_bundle_id, 0, 8)}
                      </.link>
                    <% else %>
                      <span class="text-base-content/50">none</span>
                    <% end %>
                  </td>
                  <td><.drift_status_badge resolved={event.resolved_at != nil} /></td>
                  <td><.drift_resolution_badge resolution={event.resolution} /></td>
                  <td class="text-sm">{format_datetime(event.resolved_at)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div :if={Enum.empty?(@drift_events)} class="p-8 text-center text-base-content/50">
            No drift events recorded for this node.
          </div>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp status_badge(assigns) do
    {class, text} =
      case assigns.status do
        "online" -> {"badge-success", "Online"}
        "offline" -> {"badge-error", "Offline"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp drift_alert(assigns) do
    ~H"""
    <div class="alert alert-warning">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="stroke-current shrink-0 h-6 w-6"
        fill="none"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
        />
      </svg>
      <div>
        <h3 class="font-bold">Configuration Drift Detected</h3>
        <div class="text-sm">
          Running bundle
          <%= if @node.active_bundle_id do %>
            <.link
              navigate={bundle_path(@org, @project, @node.active_bundle_id)}
              class="font-mono link"
            >
              {String.slice(@node.active_bundle_id, 0, 8)}…
            </.link>
          <% else %>
            <span class="font-mono">none</span>
          <% end %>
          but should be running
          <.link
            navigate={bundle_path(@org, @project, @node.expected_bundle_id)}
            class="font-mono link"
          >
            {String.slice(@node.expected_bundle_id, 0, 8)}…
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp node_drifted?(%Node{expected_bundle_id: nil}), do: false

  defp node_drifted?(%Node{expected_bundle_id: expected, active_bundle_id: active}) do
    expected != active
  end

  defp health_badge(assigns) do
    status = get_in(assigns.health, ["status"]) || "unknown"

    {class, text} =
      case status do
        "healthy" -> {"badge-success", "Healthy"}
        "degraded" -> {"badge-warning", "Degraded"}
        "unhealthy" -> {"badge-error", "Unhealthy"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp has_active_drift?(drift_events) do
    Enum.any?(drift_events, fn e -> is_nil(e.resolved_at) end)
  end

  defp drift_status_badge(assigns) do
    if assigns.resolved do
      ~H"""
      <span class="badge badge-sm badge-success">Resolved</span>
      """
    else
      ~H"""
      <span class="badge badge-sm badge-warning">Active</span>
      """
    end
  end

  defp drift_resolution_badge(assigns) do
    case assigns.resolution do
      "auto_corrected" ->
        ~H"""
        <span class="badge badge-sm badge-ghost">Auto-corrected</span>
        """

      "manual" ->
        ~H"""
        <span class="badge badge-sm badge-info">Manual</span>
        """

      "rollout_started" ->
        ~H"""
        <span class="badge badge-sm badge-primary">Rollout</span>
        """

      nil ->
        ~H"""
        <span class="text-base-content/50">—</span>
        """
    end
  end

  defp severity_badge(assigns) do
    {class, text} =
      case assigns.severity do
        "error" -> {"badge-error", "error"}
        "warn" -> {"badge-warning", "warn"}
        "info" -> {"badge-info", "info"}
        "debug" -> {"badge-ghost", "debug"}
        _ -> {"badge-ghost", assigns.severity || "unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_labels_for_edit(nil), do: ""

  defp format_labels_for_edit(labels) when labels == %{}, do: ""

  defp format_labels_for_edit(labels) do
    labels
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("\n")
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
