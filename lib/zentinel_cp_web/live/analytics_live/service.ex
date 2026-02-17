defmodule ZentinelCpWeb.AnalyticsLive.Service do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Analytics, Orgs, Projects, Services}

  @refresh_interval 10_000

  @impl true
  def mount(
        %{"project_slug" => slug, "service_id" => service_id} = params,
        _session,
        socket
      ) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         service when not is_nil(service) <- Services.get_service(service_id),
         true <- service.project_id == project.id do
      if connected?(socket) do
        :timer.send_interval(@refresh_interval, self(), :refresh)
      end

      time_range = 1

      {:ok,
       socket
       |> assign(
         page_title: "Analytics: #{service.name} — #{project.name}",
         org: org,
         project: project,
         service: service,
         time_range: time_range
       )
       |> load_service_analytics(service.id, time_range)}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("set_time_range", %{"range" => range}, socket) do
    hours = String.to_integer(range)
    service = socket.assigns.service

    {:noreply,
     socket
     |> assign(time_range: hours)
     |> load_service_analytics(service.id, hours)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     load_service_analytics(socket, socket.assigns.service.id, socket.assigns.time_range)}
  end

  defp load_service_analytics(socket, service_id, time_range) do
    metrics = Analytics.get_service_metrics(service_id, time_range)
    status_dist = Analytics.get_status_distribution(service_id, time_range)
    recent_logs = Analytics.get_recent_logs(service_id, limit: 50)

    # Compute aggregated stats from metrics
    agg = aggregate_metrics(metrics)

    assign(socket,
      metrics: metrics,
      status_dist: status_dist,
      recent_logs: recent_logs,
      agg: agg
    )
  end

  defp aggregate_metrics([]),
    do: %{total_requests: 0, total_errors: 0, avg_p50: nil, avg_p95: nil, avg_p99: nil}

  defp aggregate_metrics(metrics) do
    total_requests = Enum.sum(Enum.map(metrics, & &1.request_count))
    total_errors = Enum.sum(Enum.map(metrics, & &1.error_count))

    latencies_p50 = metrics |> Enum.map(& &1.latency_p50_ms) |> Enum.reject(&is_nil/1)
    latencies_p95 = metrics |> Enum.map(& &1.latency_p95_ms) |> Enum.reject(&is_nil/1)
    latencies_p99 = metrics |> Enum.map(& &1.latency_p99_ms) |> Enum.reject(&is_nil/1)

    %{
      total_requests: total_requests,
      total_errors: total_errors,
      avg_p50: safe_avg(latencies_p50),
      avg_p95: safe_avg(latencies_p95),
      avg_p99: safe_avg(latencies_p99)
    }
  end

  defp safe_avg([]), do: nil
  defp safe_avg(list), do: (Enum.sum(list) / length(list)) |> Float.round(1)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"Analytics: #{@service.name}"}
        resource_type="service"
        back_path={analytics_index_path(@org, @project)}
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
        <:stat label="Requests" value={format_number(@agg.total_requests)} />
        <:stat
          label="Error Rate"
          value={format_error_rate(@agg)}
          color={error_rate_color(@agg)}
        />
        <:stat label="p50" value={format_latency(@agg.avg_p50)} />
        <:stat label="p95" value={format_latency(@agg.avg_p95)} />
        <:stat label="p99" value={format_latency(@agg.avg_p99)} />
      </.stat_strip>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Status Code Distribution">
          <div
            :if={status_total(@status_dist) == 0}
            class="text-base-content/50 text-sm py-8 text-center"
          >
            No status code data yet.
          </div>
          <div :if={status_total(@status_dist) > 0} class="space-y-3">
            <.status_bar
              label="2xx"
              count={@status_dist[:status_2xx] || 0}
              total={status_total(@status_dist)}
              color="success"
            />
            <.status_bar
              label="3xx"
              count={@status_dist[:status_3xx] || 0}
              total={status_total(@status_dist)}
              color="info"
            />
            <.status_bar
              label="4xx"
              count={@status_dist[:status_4xx] || 0}
              total={status_total(@status_dist)}
              color="warning"
            />
            <.status_bar
              label="5xx"
              count={@status_dist[:status_5xx] || 0}
              total={status_total(@status_dist)}
              color="error"
            />
          </div>
        </.k8s_section>

        <.k8s_section title="Top Consumers">
          <div
            :if={top_consumers_list(@metrics) == []}
            class="text-base-content/50 text-sm py-8 text-center"
          >
            No consumer data yet.
          </div>
          <table :if={top_consumers_list(@metrics) != []} class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">IP</th>
                <th class="text-xs uppercase text-right">Requests</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{ip, count} <- top_consumers_list(@metrics) |> Enum.take(10)}>
                <td class="font-mono text-sm">{ip}</td>
                <td class="text-right font-mono text-sm">{count}</td>
              </tr>
            </tbody>
          </table>
        </.k8s_section>
      </div>

      <.k8s_section title="Recent Requests">
        <table :if={@recent_logs != []} class="table table-xs">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Time</th>
              <th class="text-xs uppercase">Method</th>
              <th class="text-xs uppercase">Path</th>
              <th class="text-xs uppercase text-right">Status</th>
              <th class="text-xs uppercase text-right">Latency</th>
              <th class="text-xs uppercase">Client IP</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={log <- @recent_logs}>
              <td class="text-sm">{format_timestamp(log.timestamp)}</td>
              <td class="text-sm font-mono">{log.method}</td>
              <td class="text-sm font-mono max-w-xs truncate">{log.path}</td>
              <td class={["text-right text-sm font-mono", status_color(log.status)]}>
                {log.status}
              </td>
              <td class="text-right text-sm font-mono">{format_latency(log.latency_ms)}</td>
              <td class="text-sm font-mono">{log.client_ip}</td>
            </tr>
          </tbody>
        </table>
        <div :if={@recent_logs == []} class="text-base-content/50 text-sm py-8 text-center">
          No request logs yet.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp status_bar(assigns) do
    pct = if assigns.total > 0, do: Float.round(assigns.count / assigns.total * 100, 1), else: 0

    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="flex items-center gap-3">
      <span class="w-12 text-sm font-mono">{@label}</span>
      <div class="flex-1 bg-base-300 rounded-full h-4 overflow-hidden">
        <div class={"bg-#{@color} h-full rounded-full transition-all"} style={"width: #{@pct}%"}>
        </div>
      </div>
      <span class="text-sm font-mono w-20 text-right">{@count} ({@pct}%)</span>
    </div>
    """
  end

  defp status_total(dist) do
    (dist[:status_2xx] || 0) + (dist[:status_3xx] || 0) +
      (dist[:status_4xx] || 0) + (dist[:status_5xx] || 0)
  end

  defp top_consumers_list(metrics) do
    metrics
    |> Enum.flat_map(fn m -> Map.to_list(m.top_consumers || %{}) end)
    |> Enum.reduce(%{}, fn {ip, count}, acc ->
      Map.update(acc, ip, count, &(&1 + count))
    end)
    |> Enum.sort_by(fn {_ip, count} -> count end, :desc)
  end

  defp time_range_options do
    [{"1h", 1}, {"6h", 6}, {"24h", 24}, {"7d", 168}]
  end

  defp format_number(0), do: "0"
  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: to_string(n)

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when is_number(ms) and ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_latency(ms) when is_number(ms), do: "#{round(ms)}ms"

  defp format_error_rate(%{total_requests: reqs, total_errors: errs}) when reqs > 0 do
    "#{Float.round(errs / reqs * 100, 1)}%"
  end

  defp format_error_rate(_), do: "0%"

  defp error_rate_color(%{total_requests: reqs, total_errors: errs}) when reqs > 0 do
    rate = errs / reqs * 100

    cond do
      rate > 5 -> "error"
      rate > 1 -> "warning"
      true -> nil
    end
  end

  defp error_rate_color(_), do: nil

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp status_color(status) when is_integer(status) do
    cond do
      status >= 500 -> "text-error"
      status >= 400 -> "text-warning"
      status >= 300 -> "text-info"
      true -> "text-success"
    end
  end

  defp status_color(_), do: ""

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp analytics_index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/analytics"

  defp analytics_index_path(nil, project),
    do: ~p"/projects/#{project.slug}/analytics"
end
