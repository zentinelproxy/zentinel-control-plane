defmodule ZentinelCpWeb.AnalyticsLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Analytics, Orgs, Projects, Services}

  @refresh_interval 10_000

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

        time_range = 1

        {:ok,
         socket
         |> assign(
           page_title: "Analytics — #{project.name}",
           org: org,
           project: project,
           time_range: time_range
         )
         |> load_analytics(project.id, time_range)}
    end
  end

  @impl true
  def handle_event("set_time_range", %{"range" => range}, socket) do
    hours = String.to_integer(range)
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(time_range: hours)
     |> load_analytics(project.id, hours)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_analytics(socket, socket.assigns.project.id, socket.assigns.time_range)}
  end

  defp load_analytics(socket, project_id, time_range) do
    overview = Analytics.get_project_metrics(project_id, time_range)
    top_services = Analytics.get_top_services(project_id, time_range)
    services = Services.list_services(project_id)
    service_map = Map.new(services, fn s -> {s.id, s} end)

    assign(socket,
      overview: overview,
      top_services: top_services,
      service_map: service_map
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Analytics"
        resource_type="project"
        back_path={project_path(@org, @project)}
      />

      <div class="flex gap-2">
        <button
          :for={{label, hours} <- time_range_options()}
          phx-click="set_time_range"
          phx-value-range={hours}
          class={["btn btn-xs", (@time_range == hours && "btn-primary") || "btn-ghost"]}
        >
          {label}
        </button>
      </div>

      <.stat_strip>
        <:stat label="Total Requests" value={format_number(@overview[:total_requests] || 0)} />
        <:stat
          label="Error Rate"
          value={format_error_rate(@overview)}
          color={error_rate_color(@overview)}
        />
        <:stat label="Avg p50" value={format_latency(@overview[:avg_latency_p50])} />
        <:stat label="Avg p95" value={format_latency(@overview[:avg_latency_p95])} />
        <:stat
          label="Bandwidth"
          value={
            format_bytes(
              (@overview[:total_bandwidth_in] || 0) + (@overview[:total_bandwidth_out] || 0)
            )
          }
        />
      </.stat_strip>

      <.k8s_section title="Services">
        <table :if={@top_services != []} class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Service</th>
              <th class="text-xs uppercase text-right">Requests</th>
              <th class="text-xs uppercase text-right">Errors</th>
              <th class="text-xs uppercase text-right">p50</th>
              <th class="text-xs uppercase text-right">p95</th>
              <th class="text-xs uppercase text-right">p99</th>
              <th class="text-xs uppercase text-right">Bandwidth</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={svc <- @top_services}>
              <td>
                <span class="flex items-center gap-2">
                  <.resource_badge type="service" />
                  {service_name(svc.service_id, @service_map)}
                </span>
              </td>
              <td class="text-right font-mono text-sm">{format_number(svc.total_requests || 0)}</td>
              <td class="text-right font-mono text-sm">
                <span class={svc.total_errors > 0 && "text-error"}>
                  {format_number(svc.total_errors || 0)}
                </span>
              </td>
              <td class="text-right font-mono text-sm">{format_latency(svc.avg_latency_p50)}</td>
              <td class="text-right font-mono text-sm">{format_latency(svc.avg_latency_p95)}</td>
              <td class="text-right font-mono text-sm">{format_latency(svc.avg_latency_p99)}</td>
              <td class="text-right font-mono text-sm">
                {format_bytes((svc.total_bandwidth_in || 0) + (svc.total_bandwidth_out || 0))}
              </td>
              <td>
                <.link
                  navigate={analytics_service_path(@org, @project, svc.service_id)}
                  class="btn btn-ghost btn-xs"
                >
                  Detail
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@top_services == []} class="text-base-content/50 text-sm py-8 text-center">
          No metrics data yet. Metrics are collected when nodes push data.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp time_range_options do
    [{"1h", 1}, {"6h", 6}, {"24h", 24}, {"7d", 168}]
  end

  defp service_name(service_id, service_map) do
    case Map.get(service_map, service_id) do
      nil -> String.slice(service_id, 0, 8)
      svc -> svc.name
    end
  end

  defp format_number(n) when is_nil(n), do: "0"

  defp format_number(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_number(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n) when is_integer(n), do: to_string(n)
  defp format_number(n), do: to_string(n)

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when is_number(ms) and ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_latency(ms) when is_number(ms), do: "#{round(ms)}ms"

  defp format_bytes(0), do: "0 B"

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_error_rate(%{total_requests: reqs, total_errors: errs})
       when is_integer(reqs) and reqs > 0 and is_integer(errs) do
    "#{Float.round(errs / reqs * 100, 1)}%"
  end

  defp format_error_rate(_), do: "0%"

  defp error_rate_color(%{total_requests: reqs, total_errors: errs})
       when is_integer(reqs) and reqs > 0 and is_integer(errs) do
    rate = errs / reqs * 100

    cond do
      rate > 5 -> "error"
      rate > 1 -> "warning"
      true -> nil
    end
  end

  defp error_rate_color(_), do: nil

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp project_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp analytics_service_path(%{slug: org_slug}, project, service_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/analytics/services/#{service_id}"

  defp analytics_service_path(nil, project, service_id),
    do: ~p"/projects/#{project.slug}/analytics/services/#{service_id}"
end
