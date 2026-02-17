defmodule ZentinelCpWeb.DriftLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Bundles, Bundles.Diff, Nodes, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        event = Nodes.get_drift_event!(id) |> ZentinelCp.Repo.preload(:node)

        if event.project_id != project.id do
          {:ok, push_navigate(socket, to: drift_path(org, project))}
        else
          bundle_a = Bundles.get_bundle(event.expected_bundle_id)
          bundle_b = event.actual_bundle_id && Bundles.get_bundle(event.actual_bundle_id)

          {diff_lines, diff_stats, manifest_diff} = compute_diff(bundle_a, bundle_b)

          {:ok,
           assign(socket,
             page_title: "Drift Event — #{event.node.name}",
             org: org,
             project: project,
             event: event,
             bundle_a: bundle_a,
             bundle_b: bundle_b,
             diff_lines: diff_lines,
             diff_stats: diff_stats,
             manifest_diff: manifest_diff
           )}
        end
    end
  end

  @impl true
  def handle_event("resolve", _, socket) do
    event = socket.assigns.event

    case Nodes.resolve_drift_event(event, "manual") do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:event, ZentinelCp.Repo.preload(updated, :node))
         |> put_flash(:info, "Drift event resolved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resolve drift event.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"Drift Event — #{@event.node.name}"}
        resource_type="node"
        back_path={drift_path(@org, @project)}
      >
        <:badge>
          <.severity_badge severity={@event.severity} />
          <span data-testid="resolved-status"><.status_badge event={@event} /></span>
        </:badge>
        <:action>
          <button
            :if={is_nil(@event.resolved_at)}
            phx-click="resolve"
            class="btn btn-primary btn-sm"
          >
            Resolve
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Event Details">
          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-base-content/70">Node</dt>
              <dd>
                <.link
                  navigate={node_path(@org, @project, @event.node)}
                  class="text-primary hover:underline"
                  data-testid="node-name"
                >
                  {@event.node.name}
                </.link>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/70">Detected</dt>
              <dd>{Calendar.strftime(@event.detected_at, "%Y-%m-%d %H:%M:%S")}</dd>
            </div>
            <div :if={@event.resolved_at} class="flex justify-between">
              <dt class="text-base-content/70">Resolved</dt>
              <dd>{Calendar.strftime(@event.resolved_at, "%Y-%m-%d %H:%M:%S")}</dd>
            </div>
            <div :if={@event.resolution} class="flex justify-between">
              <dt class="text-base-content/70">Resolution</dt>
              <dd><.resolution_badge resolution={@event.resolution} /></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/70">Severity</dt>
              <dd data-testid="severity"><.severity_badge severity={@event.severity} /></dd>
            </div>
          </dl>
        </.k8s_section>

        <.k8s_section title="Bundle Comparison">
          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-base-content/70">Expected Bundle</dt>
              <dd>
                <.link
                  :if={@bundle_a}
                  navigate={bundle_path(@org, @project, @event.expected_bundle_id)}
                  class="font-mono text-primary hover:underline"
                >
                  {@bundle_a.version}
                </.link>
                <span :if={is_nil(@bundle_a)} class="text-base-content/50">Not found</span>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/70">Actual Bundle</dt>
              <dd>
                <.link
                  :if={@bundle_b}
                  navigate={bundle_path(@org, @project, @event.actual_bundle_id)}
                  class="font-mono text-primary hover:underline"
                >
                  {@bundle_b.version}
                </.link>
                <span :if={is_nil(@bundle_b)} class="text-base-content/50 italic">
                  No bundle active
                </span>
              </dd>
            </div>
          </dl>
        </.k8s_section>
      </div>

      <div :if={@diff_stats} class="flex gap-4 text-sm">
        <span class="text-success">+{@diff_stats.additions} additions</span>
        <span class="text-error">-{@diff_stats.deletions} deletions</span>
        <span class="text-base-content/50">{@diff_stats.unchanged} unchanged</span>
      </div>

      <div :if={@diff_lines}>
        <.k8s_section title="Configuration Diff">
          <div class="overflow-x-auto max-h-96">
            <table class="table table-xs font-mono">
              <tbody>
                <tr :for={line <- @diff_lines} class={diff_row_class(line.type)}>
                  <td class="text-right text-base-content/40 select-none w-12 px-2">
                    {line.number_a || ""}
                  </td>
                  <td class="text-right text-base-content/40 select-none w-12 px-2">
                    {line.number_b || ""}
                  </td>
                  <td class="select-none w-6 px-1">
                    {diff_marker(line.type)}
                  </td>
                  <td class="whitespace-pre">{line.line}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </.k8s_section>
      </div>

      <div :if={@manifest_diff}>
        <.k8s_section title="Manifest Diff">
          <div :if={@manifest_diff.added != []} class="mb-2">
            <h3 class="text-sm font-medium text-success mb-1">Added files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.added}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.removed != []} class="mb-2">
            <h3 class="text-sm font-medium text-error mb-1">Removed files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.removed}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.modified != []} class="mb-2">
            <h3 class="text-sm font-medium text-warning mb-1">Modified files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.modified}>{f}</li>
            </ul>
          </div>
          <div
            :if={
              @manifest_diff.added == [] and @manifest_diff.removed == [] and
                @manifest_diff.modified == []
            }
            class="text-base-content/50 text-sm"
          >
            No manifest changes.
          </div>
        </.k8s_section>
      </div>

      <div :if={is_nil(@bundle_b)} class="text-center py-12 text-base-content/50">
        <p class="text-lg font-medium">No active bundle on this node</p>
        <p class="text-sm mt-2">
          The node has no configuration bundle deployed. This is a critical drift state.
        </p>
      </div>

      <div :if={is_nil(@bundle_a)} class="text-center py-12 text-base-content/50">
        <p class="text-lg font-medium">Expected bundle not found</p>
        <p class="text-sm mt-2">
          The expected bundle may have been deleted.
        </p>
      </div>
    </div>
    """
  end

  defp compute_diff(nil, _), do: {nil, nil, nil}
  defp compute_diff(_, nil), do: {nil, nil, nil}

  defp compute_diff(bundle_a, bundle_b) do
    config_diff = Diff.config_diff(bundle_a, bundle_b)
    lines = Diff.annotate_diff(config_diff)
    stats = Diff.diff_stats(config_diff)
    manifest = Diff.manifest_diff(bundle_a, bundle_b)
    {lines, stats, manifest}
  end

  defp diff_row_class(:ins), do: "bg-success/10"
  defp diff_row_class(:del), do: "bg-error/10"
  defp diff_row_class(_), do: ""

  defp diff_marker(:ins), do: "+"
  defp diff_marker(:del), do: "-"
  defp diff_marker(_), do: " "

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
    <span class={"badge badge-sm #{@class}"}>{String.capitalize(@severity || "unknown")}</span>
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

  defp drift_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/drift"

  defp drift_path(nil, project),
    do: ~p"/projects/#{project.slug}/drift"

  defp node_path(%{slug: org_slug}, project, node),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"

  defp node_path(nil, project, node),
    do: ~p"/projects/#{project.slug}/nodes/#{node.id}"

  defp bundle_path(%{slug: org_slug}, project, bundle_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle_id}"

  defp bundle_path(nil, project, bundle_id),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle_id}"
end
