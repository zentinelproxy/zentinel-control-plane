defmodule ZentinelCpWeb.WafLive.Anomalies do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Analytics, Orgs, Projects}

  @refresh_interval 30_000

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          :timer.send_interval(@refresh_interval, self(), :refresh)
        end

        {:ok,
         socket
         |> assign(
           page_title: "WAF Anomalies — #{project.name}",
           org: org,
           project: project,
           status_filter: "active"
         )
         |> load_data()}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(status_filter: status) |> load_data()}
  end

  @impl true
  def handle_event("acknowledge", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Analytics.acknowledge_anomaly(id, user.id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Anomaly acknowledged.") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not acknowledge anomaly.")}
    end
  end

  @impl true
  def handle_event("resolve", %{"id" => id}, socket) do
    case Analytics.resolve_anomaly(id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Anomaly resolved.") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not resolve anomaly.")}
    end
  end

  @impl true
  def handle_event("false_positive", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Analytics.mark_false_positive(id, user.id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Marked as false positive.") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark as false positive.")}
    end
  end

  defp load_data(socket) do
    project = socket.assigns.project
    status_filter = socket.assigns.status_filter

    anomalies = Analytics.list_waf_anomalies(project.id, status: status_filter)
    stats = Analytics.get_anomaly_stats(project.id)

    assign(socket, anomalies: anomalies, anomaly_stats: stats)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">WAF Anomalies</h1>
        <.link navigate={waf_path(@org, @project)} class="btn btn-ghost btn-sm">
          Back to WAF Events
        </.link>
      </div>

      <.stat_strip>
        <:stat label="Active" value={to_string(@anomaly_stats.active)} color="error" />
        <:stat label="Acknowledged" value={to_string(@anomaly_stats.acknowledged)} color="warning" />
        <:stat label="Resolved" value={to_string(@anomaly_stats.resolved)} color="success" />
        <:stat label="False Positive" value={to_string(@anomaly_stats.false_positive)} />
      </.stat_strip>

      <.k8s_section title="Anomalies">
        <div class="flex gap-1 mb-4">
          <button
            :for={status <- ~w(active acknowledged resolved false_positive)}
            phx-click="filter_status"
            phx-value-status={status}
            class={["btn btn-xs", if(@status_filter == status, do: "btn-primary", else: "btn-ghost")]}
          >
            {status}
          </button>
        </div>

        <div :if={@anomalies == []} class="text-center py-8 text-base-content/50 text-sm">
          No anomalies with status "{@status_filter}".
        </div>

        <div :for={anomaly <- @anomalies} class="border border-base-300 rounded-lg p-4 mb-3">
          <div class="flex items-start justify-between">
            <div class="space-y-1">
              <div class="flex items-center gap-2">
                <span class={["badge badge-sm", severity_class(anomaly.severity)]}>
                  {anomaly.severity}
                </span>
                <span class="badge badge-sm badge-outline">{anomaly.anomaly_type}</span>
                <span class={["badge badge-sm", status_class(anomaly.status)]}>
                  {anomaly.status}
                </span>
              </div>
              <p class="text-sm">{anomaly.description}</p>
              <div class="flex gap-4 text-xs text-base-content/60">
                <span>Detected: {format_datetime(anomaly.detected_at)}</span>
                <span :if={anomaly.observed_value}>
                  Observed: {Float.round(anomaly.observed_value, 1)}
                </span>
                <span :if={anomaly.expected_mean}>
                  Expected: {Float.round(anomaly.expected_mean, 1)} +/- {Float.round(
                    anomaly.expected_stddev || 0.0,
                    1
                  )}
                </span>
                <span :if={anomaly.deviation_sigma}>
                  Deviation: {anomaly.deviation_sigma} sigma
                </span>
              </div>
            </div>
            <div :if={anomaly.status == "active"} class="flex gap-1">
              <button
                phx-click="acknowledge"
                phx-value-id={anomaly.id}
                class="btn btn-ghost btn-xs"
              >
                Acknowledge
              </button>
              <button
                phx-click="resolve"
                phx-value-id={anomaly.id}
                data-confirm="Are you sure you want to resolve this anomaly?"
                class="btn btn-ghost btn-xs"
              >
                Resolve
              </button>
              <button
                phx-click="false_positive"
                phx-value-id={anomaly.id}
                data-confirm="Mark this anomaly as a false positive?"
                class="btn btn-ghost btn-xs"
              >
                False Positive
              </button>
            </div>
            <div :if={anomaly.status == "acknowledged"} class="flex gap-1">
              <button
                phx-click="resolve"
                phx-value-id={anomaly.id}
                data-confirm="Are you sure you want to resolve this anomaly?"
                class="btn btn-ghost btn-xs"
              >
                Resolve
              </button>
            </div>
          </div>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp waf_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf"

  defp waf_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf"

  defp severity_class("critical"), do: "badge-error"
  defp severity_class("high"), do: "badge-error"
  defp severity_class("medium"), do: "badge-warning"
  defp severity_class("low"), do: "badge-info"
  defp severity_class(_), do: "badge-ghost"

  defp status_class("active"), do: "badge-error"
  defp status_class("acknowledged"), do: "badge-warning"
  defp status_class("resolved"), do: "badge-success"
  defp status_class("false_positive"), do: "badge-ghost"
  defp status_class(_), do: "badge-ghost"

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
