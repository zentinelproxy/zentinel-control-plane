defmodule ZentinelCpWeb.DriftLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Nodes, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "drift:#{project.id}")
        end

        {:ok, load_data(socket, org, project, nil)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status_filter = params["status"]
    {:noreply, load_data(socket, socket.assigns.org, socket.assigns.project, status_filter)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    path = build_path(socket.assigns.org, socket.assigns.project, status)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("resolve", %{"id" => id}, socket) do
    event = Nodes.get_drift_event!(id)

    case Nodes.resolve_drift_event(event, "manual") do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_data(socket.assigns.org, socket.assigns.project, socket.assigns.status_filter)
         |> put_flash(:info, "Drift event resolved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resolve drift event.")}
    end
  end

  @impl true
  def handle_event("resolve_all", _, socket) do
    project = socket.assigns.project
    events = Nodes.list_drift_events(project.id, include_resolved: false)

    resolved_count =
      Enum.reduce(events, 0, fn event, count ->
        case Nodes.resolve_drift_event(event, "manual") do
          {:ok, _} -> count + 1
          _ -> count
        end
      end)

    {:noreply,
     socket
     |> load_data(socket.assigns.org, project, socket.assigns.status_filter)
     |> put_flash(:info, "Resolved #{resolved_count} drift event(s).")}
  end

  @impl true
  def handle_info({:drift_event, _type, _node_id}, socket) do
    {:noreply,
     load_data(socket, socket.assigns.org, socket.assigns.project, socket.assigns.status_filter)}
  end

  defp load_data(socket, org, project, status_filter) do
    opts =
      case status_filter do
        "active" -> [include_resolved: false]
        "resolved" -> [include_resolved: true]
        _ -> [include_resolved: true]
      end

    events = Nodes.list_drift_events(project.id, opts)

    # Filter to only resolved if that filter is selected
    events =
      if status_filter == "resolved" do
        Enum.filter(events, fn e -> e.resolved_at != nil end)
      else
        events
      end

    drift_stats = Nodes.get_drift_stats(project.id)
    active_count = Enum.count(events, fn e -> is_nil(e.resolved_at) end)
    resolved_count = count_resolved_events(project.id)

    assign(socket,
      page_title: "Drift Events — #{project.name}",
      org: org,
      project: project,
      events: events,
      drift_stats: drift_stats,
      status_filter: status_filter,
      active_count: active_count,
      resolved_count: resolved_count
    )
  end

  defp count_resolved_events(project_id) do
    project_id
    |> Nodes.list_drift_events(include_resolved: true)
    |> Enum.count(fn e -> e.resolved_at != nil end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Drift Events</h1>
        </:filters>
        <:actions>
          <.link navigate={export_path(@org, @project, "json")} class="btn btn-ghost btn-sm">
            Export JSON
          </.link>
          <.link navigate={export_path(@org, @project, "csv")} class="btn btn-ghost btn-sm">
            Export CSV
          </.link>
          <form phx-change="filter" class="flex items-center gap-2">
            <select name="status" class="select select-bordered select-sm">
              <option value="" selected={@status_filter == nil}>All</option>
              <option value="active" selected={@status_filter == "active"}>Active</option>
              <option value="resolved" selected={@status_filter == "resolved"}>Resolved</option>
            </select>
          </form>
          <button
            :if={@active_count > 0}
            phx-click="resolve_all"
            data-confirm="Are you sure you want to resolve all active drift events?"
            class="btn btn-outline btn-sm"
          >
            Resolve All ({@active_count})
          </button>
        </:actions>
      </.table_toolbar>

      <div data-testid="drift-stats">
        <.stat_strip>
          <:stat
            label="Active Drifts"
            value={to_string(@active_count)}
            color={if @active_count > 0, do: "warning"}
          />
          <:stat label="Resolved" value={to_string(@resolved_count)} />
          <:stat label="Managed Nodes" value={to_string(@drift_stats.total_managed)} color="info" />
        </.stat_strip>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Node</th>
              <th class="text-xs uppercase">Severity</th>
              <th class="text-xs uppercase">Expected Bundle</th>
              <th class="text-xs uppercase">Actual Bundle</th>
              <th class="text-xs uppercase">Detected</th>
              <th class="text-xs uppercase">Status</th>
              <th class="text-xs uppercase">Resolution</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={event <- @events} class="hover" data-testid="drift-event-row">
              <td>
                <.link
                  navigate={node_path(@org, @project, event.node)}
                  class="flex items-center gap-2 text-primary hover:underline"
                >
                  <.resource_badge type="node" />
                  {event.node.name}
                </.link>
              </td>
              <td>
                <.severity_badge severity={event.severity} />
              </td>
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
              <td class="text-sm">
                <.link
                  navigate={event_path(@org, @project, event)}
                  class="hover:underline"
                >
                  {Calendar.strftime(event.detected_at, "%Y-%m-%d %H:%M")}
                </.link>
              </td>
              <td>
                <.status_badge event={event} />
              </td>
              <td>
                <.resolution_badge resolution={event.resolution} />
              </td>
              <td class="flex gap-1">
                <.link
                  navigate={event_path(@org, @project, event)}
                  class="btn btn-ghost btn-xs"
                >
                  View
                </.link>
                <button
                  :if={is_nil(event.resolved_at)}
                  phx-click="resolve"
                  phx-value-id={event.id}
                  class="btn btn-ghost btn-xs"
                >
                  Resolve
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div
          :if={@events == []}
          class="text-center py-12 text-base-content/50"
          data-testid="no-active-drift"
        >
          No drift events found.
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    if assigns.event.resolved_at do
      ~H"""
      <span class="badge badge-sm badge-success">Resolved</span>
      """
    else
      ~H"""
      <span class="badge badge-sm badge-warning">Active</span>
      """
    end
  end

  defp severity_badge(assigns) do
    class =
      case assigns.severity do
        "critical" -> "badge-error"
        "high" -> "badge-warning"
        "medium" -> "badge-info"
        "low" -> "badge-ghost"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <span class={"badge badge-sm #{@class}"} data-testid="severity-badge">
      {String.capitalize(@severity || "unknown")}
    </span>
    """
  end

  defp resolution_badge(assigns) do
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
        <span class="badge badge-sm badge-primary">Rollout Started</span>
        """

      "rollout_completed" ->
        ~H"""
        <span class="badge badge-sm badge-success">Rollout Completed</span>
        """

      nil ->
        ~H"""
        <span class="text-base-content/50">—</span>
        """
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp node_path(%{slug: org_slug}, project, node),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"

  defp node_path(nil, project, node),
    do: ~p"/projects/#{project.slug}/nodes/#{node.id}"

  defp bundle_path(%{slug: org_slug}, project, bundle_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle_id}"

  defp bundle_path(nil, project, bundle_id),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle_id}"

  defp event_path(%{slug: org_slug}, project, event),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/drift/#{event.id}"

  defp event_path(nil, project, event),
    do: ~p"/projects/#{project.slug}/drift/#{event.id}"

  defp export_path(_org, project, format),
    do: ~p"/api/v1/projects/#{project.slug}/drift/export?format=#{format}"

  defp build_path(org, project, nil), do: drift_path(org, project)
  defp build_path(org, project, ""), do: drift_path(org, project)
  defp build_path(org, project, status), do: "#{drift_path(org, project)}?status=#{status}"

  defp drift_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/drift"

  defp drift_path(nil, project),
    do: ~p"/projects/#{project.slug}/drift"
end
