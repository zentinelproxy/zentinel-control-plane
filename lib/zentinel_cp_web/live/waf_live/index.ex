defmodule ZentinelCpWeb.WafLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Analytics, Orgs, Projects}

  @refresh_interval 15_000

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          :timer.send_interval(@refresh_interval, self(), :refresh)
          Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "waf:#{project.id}")
        end

        filters = %{
          rule_type: nil,
          action: nil,
          severity: nil,
          client_ip: nil,
          time_range: 24
        }

        {:ok,
         socket
         |> assign(
           page_title: "WAF Events — #{project.name}",
           org: org,
           project: project,
           filters: filters,
           page: 1
         )
         |> load_data()}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:waf_event, _}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      rule_type: blank_to_nil(params["rule_type"]),
      action: blank_to_nil(params["action"]),
      severity: blank_to_nil(params["severity"]),
      client_ip: blank_to_nil(params["client_ip"]),
      time_range: String.to_integer(params["time_range"] || "24")
    }

    {:noreply, socket |> assign(filters: filters, page: 1) |> load_data()}
  end

  @impl true
  def handle_event("next_page", _, socket) do
    {:noreply, socket |> assign(page: socket.assigns.page + 1) |> load_events()}
  end

  @impl true
  def handle_event("prev_page", _, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(page: page) |> load_events()}
  end

  defp load_data(socket) do
    project = socket.assigns.project
    filters = socket.assigns.filters

    stats = Analytics.get_waf_event_stats(project.id, filters.time_range)
    top_ips = Analytics.get_top_blocked_ips(project.id, filters.time_range, 5)
    top_paths = Analytics.get_top_blocked_paths(project.id, filters.time_range, 5)

    bucket_minutes = bucket_size_for_range(filters.time_range)
    time_series = Analytics.get_waf_time_series(project.id, filters.time_range, bucket_minutes)
    chart_data = build_chart_data(time_series)

    socket
    |> assign(
      stats: stats,
      top_ips: top_ips,
      top_paths: top_paths,
      time_series: chart_data
    )
    |> load_events()
  end

  defp bucket_size_for_range(1), do: 5
  defp bucket_size_for_range(6), do: 15
  defp bucket_size_for_range(24), do: 60
  defp bucket_size_for_range(168), do: 360
  defp bucket_size_for_range(_), do: 60

  defp build_chart_data(time_series) do
    # Group by bucket, then build per-bucket breakdown by rule_type
    by_bucket =
      Enum.group_by(time_series, & &1.bucket)
      |> Enum.sort_by(fn {bucket, _} -> bucket end)

    max_total =
      case by_bucket do
        [] ->
          1

        buckets ->
          buckets
          |> Enum.map(fn {_, items} -> items |> Enum.map(& &1.count) |> Enum.sum() end)
          |> Enum.max(fn -> 1 end)
      end

    buckets =
      Enum.map(by_bucket, fn {bucket, items} ->
        total = Enum.sum(Enum.map(items, & &1.count))
        segments = Enum.map(items, fn item -> %{rule_type: item.rule_type, count: item.count} end)
        %{bucket: bucket, total: total, segments: segments}
      end)

    %{buckets: buckets, max: max_total}
  end

  defp load_events(socket) do
    project = socket.assigns.project
    filters = socket.assigns.filters
    page = socket.assigns.page
    per_page = 25

    events =
      Analytics.list_waf_events(project.id,
        rule_type: filters.rule_type,
        action: filters.action,
        severity: filters.severity,
        client_ip: filters.client_ip,
        time_range: filters.time_range,
        limit: per_page,
        offset: (page - 1) * per_page
      )

    assign(socket, events: events, per_page: per_page)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">WAF Events</h1>
        <.link navigate={anomalies_path(@org, @project)} class="btn btn-outline btn-sm">
          Anomalies
        </.link>
      </div>

      <.stat_strip>
        <:stat label="Total Events" value={to_string(@stats.total)} />
        <:stat label="Blocked" value={to_string(@stats.blocked)} color="error" />
        <:stat label="Logged" value={to_string(@stats.logged)} color="warning" />
        <:stat label="Unique IPs" value={to_string(@stats.unique_ips)} color="info" />
      </.stat_strip>

      <.k8s_section title="Event Timeline" testid="waf-timeline">
        <div :if={@time_series.buckets == []} class="text-base-content/50 text-sm py-4 text-center">
          No events in this time range.
        </div>
        <div
          :if={@time_series.buckets != []}
          class="flex items-end gap-px h-32"
          title="WAF event timeline"
        >
          <div
            :for={bucket <- @time_series.buckets}
            class="flex-1 flex flex-col-reverse min-w-[4px]"
            style={"height: #{bar_height(bucket.total, @time_series.max)}%"}
            title={"#{format_bucket_label(bucket.bucket)}: #{bucket.total} events"}
          >
            <div
              :for={seg <- bucket.segments}
              class={["w-full", rule_type_color(seg.rule_type)]}
              style={"height: #{bar_height(seg.count, bucket.total)}%"}
            >
            </div>
          </div>
        </div>
        <div
          :if={@time_series.buckets != []}
          class="flex justify-between text-[10px] text-base-content/40 mt-1"
        >
          <span>{format_bucket_label(List.first(@time_series.buckets).bucket)}</span>
          <span>{format_bucket_label(List.last(@time_series.buckets).bucket)}</span>
        </div>
        <div
          :if={@time_series.buckets != []}
          class="flex flex-wrap gap-3 mt-2 text-[10px] text-base-content/60"
        >
          <span :for={rt <- ~w(sqli xss rfi lfi rce scanner custom)} class="flex items-center gap-1">
            <span class={["inline-block w-2 h-2 rounded-sm", rule_type_color(rt)]}></span>
            {rt}
          </span>
        </div>
      </.k8s_section>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Top Blocked IPs">
          <table :if={@top_ips != []} class="table table-sm">
            <thead>
              <tr>
                <th class="text-xs">IP</th>
                <th class="text-xs">Count</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{ip, count} <- @top_ips}>
                <td class="font-mono text-sm">{ip}</td>
                <td class="text-sm">{count}</td>
              </tr>
            </tbody>
          </table>
          <div :if={@top_ips == []} class="text-base-content/50 text-sm py-4 text-center">
            No blocked IPs yet.
          </div>
        </.k8s_section>

        <.k8s_section title="Top Blocked Paths">
          <table :if={@top_paths != []} class="table table-sm">
            <thead>
              <tr>
                <th class="text-xs">Path</th>
                <th class="text-xs">Count</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{path, count} <- @top_paths}>
                <td class="font-mono text-sm truncate max-w-xs">{path}</td>
                <td class="text-sm">{count}</td>
              </tr>
            </tbody>
          </table>
          <div :if={@top_paths == []} class="text-base-content/50 text-sm py-4 text-center">
            No blocked paths yet.
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Events">
        <form phx-change="filter" class="flex flex-wrap gap-2 mb-4">
          <select name="time_range" class="select select-bordered select-xs">
            <option value="1" selected={@filters.time_range == 1}>1h</option>
            <option value="6" selected={@filters.time_range == 6}>6h</option>
            <option value="24" selected={@filters.time_range == 24}>24h</option>
            <option value="168" selected={@filters.time_range == 168}>7d</option>
          </select>
          <select name="rule_type" class="select select-bordered select-xs">
            <option value="">All Types</option>
            <option
              :for={rt <- ~w(sqli xss rfi lfi rce scanner custom)}
              value={rt}
              selected={@filters.rule_type == rt}
            >
              {rt}
            </option>
          </select>
          <select name="action" class="select select-bordered select-xs">
            <option value="">All Actions</option>
            <option
              :for={a <- ~w(blocked logged challenged)}
              value={a}
              selected={@filters.action == a}
            >
              {a}
            </option>
          </select>
          <select name="severity" class="select select-bordered select-xs">
            <option value="">All Severities</option>
            <option
              :for={s <- ~w(critical high medium low)}
              value={s}
              selected={@filters.severity == s}
            >
              {s}
            </option>
          </select>
          <input
            type="text"
            name="client_ip"
            value={@filters.client_ip}
            placeholder="Filter by IP"
            class="input input-bordered input-xs w-36"
          />
        </form>

        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Time</th>
              <th class="text-xs">Type</th>
              <th class="text-xs">Action</th>
              <th class="text-xs">Severity</th>
              <th class="text-xs">Client IP</th>
              <th class="text-xs">Method</th>
              <th class="text-xs">Path</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={event <- @events}
              class="hover:bg-base-200 cursor-pointer"
              phx-click={JS.navigate(event_path(@org, @project, event))}
            >
              <td class="text-xs whitespace-nowrap">{format_timestamp(event.timestamp)}</td>
              <td><span class="badge badge-xs badge-outline">{event.rule_type}</span></td>
              <td>
                <span class={["badge badge-xs", action_class(event.action)]}>
                  {event.action}
                </span>
              </td>
              <td>
                <span :if={event.severity} class={["badge badge-xs", severity_class(event.severity)]}>
                  {event.severity}
                </span>
              </td>
              <td class="font-mono text-xs">{event.client_ip || "—"}</td>
              <td class="text-xs">{event.method || "—"}</td>
              <td class="text-xs font-mono truncate max-w-[200px]">{event.path || "—"}</td>
            </tr>
          </tbody>
        </table>

        <div :if={@events == []} class="text-base-content/50 text-sm py-4 text-center">
          No WAF events found.
        </div>

        <div
          :if={@events != []}
          class="flex justify-between items-center mt-4 pt-3 border-t border-base-300"
        >
          <button :if={@page > 1} phx-click="prev_page" class="btn btn-ghost btn-xs">Previous</button>
          <span :if={@page <= 1}></span>
          <span class="text-xs text-base-content/50">Page {@page}</span>
          <button
            :if={length(@events) == @per_page}
            phx-click="next_page"
            class="btn btn-ghost btn-xs"
          >
            Next
          </button>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp anomalies_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/anomalies"

  defp anomalies_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf/anomalies"

  defp event_path(%{slug: org_slug}, project, event),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/#{event.id}"

  defp event_path(nil, project, event),
    do: ~p"/projects/#{project.slug}/waf/#{event.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp action_class("blocked"), do: "badge-error"
  defp action_class("challenged"), do: "badge-warning"
  defp action_class(_), do: "badge-info"

  defp severity_class("critical"), do: "badge-error"
  defp severity_class("high"), do: "badge-error"
  defp severity_class("medium"), do: "badge-warning"
  defp severity_class("low"), do: "badge-info"
  defp severity_class(_), do: "badge-ghost"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp bar_height(_value, 0), do: 0
  defp bar_height(value, max), do: round(value / max * 100)

  defp format_bucket_label(nil), do: ""

  defp format_bucket_label(bucket) when is_binary(bucket) do
    case NaiveDateTime.from_iso8601(bucket) do
      {:ok, dt} -> Calendar.strftime(dt, "%H:%M")
      _ -> bucket
    end
  end

  defp rule_type_color("sqli"), do: "bg-error"
  defp rule_type_color("xss"), do: "bg-warning"
  defp rule_type_color("rfi"), do: "bg-orange-500"
  defp rule_type_color("lfi"), do: "bg-amber-500"
  defp rule_type_color("rce"), do: "bg-red-800"
  defp rule_type_color("scanner"), do: "bg-info"
  defp rule_type_color("custom"), do: "bg-secondary"
  defp rule_type_color(_), do: "bg-base-content/30"
end
