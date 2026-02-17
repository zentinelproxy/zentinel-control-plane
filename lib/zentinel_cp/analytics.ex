defmodule ZentinelCp.Analytics do
  @moduledoc """
  The Analytics context for request-level metrics and logs.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.{ServiceMetric, RequestLog, WafEvent, WafBaseline, WafAnomaly}

  ## Ingestion

  @doc """
  Bulk inserts metric records from a node push.
  """
  def ingest_metrics(metrics_list) when is_list(metrics_list) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(metrics_list, fn attrs ->
        %{
          id: Ecto.UUID.generate(),
          service_id: attrs["service_id"],
          project_id: attrs["project_id"],
          period_start: parse_datetime(attrs["period_start"]),
          period_seconds: attrs["period_seconds"] || 60,
          request_count: attrs["request_count"] || 0,
          error_count: attrs["error_count"] || 0,
          latency_p50_ms: attrs["latency_p50_ms"],
          latency_p95_ms: attrs["latency_p95_ms"],
          latency_p99_ms: attrs["latency_p99_ms"],
          bandwidth_in_bytes: attrs["bandwidth_in_bytes"] || 0,
          bandwidth_out_bytes: attrs["bandwidth_out_bytes"] || 0,
          status_2xx: attrs["status_2xx"] || 0,
          status_3xx: attrs["status_3xx"] || 0,
          status_4xx: attrs["status_4xx"] || 0,
          status_5xx: attrs["status_5xx"] || 0,
          top_paths: attrs["top_paths"] || %{},
          top_consumers: attrs["top_consumers"] || %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(ServiceMetric, entries)
    {:ok, count}
  end

  @doc """
  Bulk inserts request log entries from a node push.
  """
  def ingest_request_logs(logs_list) when is_list(logs_list) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(logs_list, fn attrs ->
        %{
          id: Ecto.UUID.generate(),
          service_id: attrs["service_id"],
          project_id: attrs["project_id"],
          node_id: attrs["node_id"],
          timestamp: parse_datetime_usec(attrs["timestamp"]),
          method: attrs["method"],
          path: attrs["path"],
          status: attrs["status"],
          latency_ms: attrs["latency_ms"],
          client_ip: attrs["client_ip"],
          user_agent: attrs["user_agent"],
          request_size: attrs["request_size"],
          response_size: attrs["response_size"],
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(RequestLog, entries)
    {:ok, count}
  end

  ## Queries

  @doc """
  Returns time-series metrics for a service within a time range.
  """
  def get_service_metrics(service_id, time_range, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    {start_time, end_time} = resolve_time_range(time_range)

    from(m in ServiceMetric,
      where: m.service_id == ^service_id,
      where: m.period_start >= ^start_time,
      where: m.period_start <= ^end_time,
      order_by: [asc: m.period_start],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns aggregated metrics across all services in a project for a time range.
  """
  def get_project_metrics(project_id, time_range) do
    {start_time, end_time} = resolve_time_range(time_range)

    from(m in ServiceMetric,
      where: m.project_id == ^project_id,
      where: m.period_start >= ^start_time,
      where: m.period_start <= ^end_time,
      select: %{
        total_requests: sum(m.request_count),
        total_errors: sum(m.error_count),
        avg_latency_p50: avg(m.latency_p50_ms),
        avg_latency_p95: avg(m.latency_p95_ms),
        avg_latency_p99: avg(m.latency_p99_ms),
        total_bandwidth_in: sum(m.bandwidth_in_bytes),
        total_bandwidth_out: sum(m.bandwidth_out_bytes),
        total_2xx: sum(m.status_2xx),
        total_3xx: sum(m.status_3xx),
        total_4xx: sum(m.status_4xx),
        total_5xx: sum(m.status_5xx)
      }
    )
    |> Repo.one()
    |> normalize_aggregation()
  end

  @doc """
  Returns per-service metrics sorted by request count for a project.
  """
  def get_top_services(project_id, time_range) do
    {start_time, end_time} = resolve_time_range(time_range)

    from(m in ServiceMetric,
      where: m.project_id == ^project_id,
      where: m.period_start >= ^start_time,
      where: m.period_start <= ^end_time,
      group_by: m.service_id,
      select: %{
        service_id: m.service_id,
        total_requests: sum(m.request_count),
        total_errors: sum(m.error_count),
        avg_latency_p50: avg(m.latency_p50_ms),
        avg_latency_p95: avg(m.latency_p95_ms),
        avg_latency_p99: avg(m.latency_p99_ms),
        total_bandwidth_in: sum(m.bandwidth_in_bytes),
        total_bandwidth_out: sum(m.bandwidth_out_bytes)
      },
      order_by: [desc: sum(m.request_count)]
    )
    |> Repo.all()
  end

  @doc """
  Returns status code distribution for a service.
  """
  def get_status_distribution(service_id, time_range) do
    {start_time, end_time} = resolve_time_range(time_range)

    from(m in ServiceMetric,
      where: m.service_id == ^service_id,
      where: m.period_start >= ^start_time,
      where: m.period_start <= ^end_time,
      select: %{
        status_2xx: sum(m.status_2xx),
        status_3xx: sum(m.status_3xx),
        status_4xx: sum(m.status_4xx),
        status_5xx: sum(m.status_5xx)
      }
    )
    |> Repo.one()
    |> normalize_aggregation()
  end

  @doc """
  Returns recent request logs for a service.
  """
  def get_recent_logs(service_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(l in RequestLog,
      where: l.service_id == ^service_id,
      order_by: [desc: l.timestamp],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Deletes request logs older than the retention period.
  Returns the number of deleted records.
  """
  def prune_old_logs(retention_hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_hours * 3600, :second)

    {count, _} =
      from(l in RequestLog, where: l.timestamp < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  ## WAF Events

  @doc """
  Gets a single WAF event by ID.
  """
  def get_waf_event(id), do: Repo.get(WafEvent, id)

  @doc """
  Bulk inserts WAF event records from a node push.
  """
  def ingest_waf_events(events_list) when is_list(events_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(events_list, fn attrs ->
        %{
          id: Ecto.UUID.generate(),
          project_id: attrs["project_id"],
          service_id: attrs["service_id"],
          node_id: attrs["node_id"],
          timestamp: parse_datetime_usec(attrs["timestamp"]),
          rule_type: attrs["rule_type"],
          rule_id: attrs["rule_id"],
          action: attrs["action"],
          severity: attrs["severity"],
          client_ip: attrs["client_ip"],
          method: attrs["method"],
          path: attrs["path"],
          matched_data: attrs["matched_data"],
          user_agent: attrs["user_agent"],
          geo_country: attrs["geo_country"],
          request_headers: attrs["request_headers"] || %{},
          metadata: attrs["metadata"] || %{},
          inserted_at: now
        }
      end)

    {count, _} = Repo.insert_all(WafEvent, entries)

    # Broadcast & emit events
    project_ids = entries |> Enum.map(& &1.project_id) |> Enum.uniq()

    for pid <- project_ids do
      Phoenix.PubSub.broadcast(ZentinelCp.PubSub, "waf:#{pid}", {:waf_event, pid})
    end

    blocked_count = Enum.count(entries, &(&1.action == "blocked"))

    if blocked_count > 0 do
      for pid <- project_ids do
        ZentinelCp.Events.emit("security.waf_blocked", %{count: blocked_count}, project_id: pid)
      end
    end

    {:ok, count}
  end

  @doc """
  Lists WAF events for a project with optional filters and pagination.
  """
  def list_waf_events(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    time_range = Keyword.get(opts, :time_range, 24)

    {start_time, end_time} = resolve_time_range(time_range)

    query =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.timestamp >= ^start_time,
        where: e.timestamp <= ^end_time,
        order_by: [desc: e.timestamp],
        limit: ^limit,
        offset: ^offset
      )

    query =
      Enum.reduce(opts, query, fn
        {:rule_type, rt}, q when is_binary(rt) -> where(q, [e], e.rule_type == ^rt)
        {:action, a}, q when is_binary(a) -> where(q, [e], e.action == ^a)
        {:severity, s}, q when is_binary(s) -> where(q, [e], e.severity == ^s)
        {:client_ip, ip}, q when is_binary(ip) -> where(q, [e], e.client_ip == ^ip)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Returns WAF event statistics for a project within a time range.
  """
  def get_waf_event_stats(project_id, time_range_hours \\ 24) do
    {start_time, end_time} = resolve_time_range(time_range_hours)

    stats =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.timestamp >= ^start_time,
        where: e.timestamp <= ^end_time,
        select: %{
          total: count(e.id),
          blocked: count(fragment("CASE WHEN ? = 'blocked' THEN 1 END", e.action)),
          logged: count(fragment("CASE WHEN ? = 'logged' THEN 1 END", e.action)),
          challenged: count(fragment("CASE WHEN ? = 'challenged' THEN 1 END", e.action)),
          unique_ips: count(e.client_ip, :distinct)
        }
      )
      |> Repo.one()

    stats || %{total: 0, blocked: 0, logged: 0, challenged: 0, unique_ips: 0}
  end

  @doc """
  Returns the top blocked client IPs for a project.
  """
  def get_top_blocked_ips(project_id, time_range_hours \\ 24, limit \\ 10) do
    {start_time, end_time} = resolve_time_range(time_range_hours)

    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.action == "blocked",
      where: e.timestamp >= ^start_time,
      where: e.timestamp <= ^end_time,
      where: not is_nil(e.client_ip),
      group_by: e.client_ip,
      select: {e.client_ip, count(e.id)},
      order_by: [desc: count(e.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns the top blocked paths for a project.
  """
  def get_top_blocked_paths(project_id, time_range_hours \\ 24, limit \\ 10) do
    {start_time, end_time} = resolve_time_range(time_range_hours)

    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.action == "blocked",
      where: e.timestamp >= ^start_time,
      where: e.timestamp <= ^end_time,
      where: not is_nil(e.path),
      group_by: e.path,
      select: {e.path, count(e.id)},
      order_by: [desc: count(e.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns time-series WAF event counts grouped by rule_type.
  """
  def get_waf_time_series(project_id, time_range_hours \\ 24, bucket_minutes \\ 60) do
    {start_time, end_time} = resolve_time_range(time_range_hours)
    bucket_seconds = bucket_minutes * 60

    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.timestamp >= ^start_time,
      where: e.timestamp <= ^end_time,
      group_by: [
        fragment("(strftime('%s', ?) / ? * ?)", e.timestamp, ^bucket_seconds, ^bucket_seconds),
        e.rule_type
      ],
      select: %{
        bucket:
          fragment(
            "datetime((strftime('%s', ?) / ? * ?), 'unixepoch')",
            e.timestamp,
            ^bucket_seconds,
            ^bucket_seconds
          ),
        rule_type: e.rule_type,
        count: count(e.id)
      },
      order_by: [
        asc:
          fragment("(strftime('%s', ?) / ? * ?)", e.timestamp, ^bucket_seconds, ^bucket_seconds)
      ]
    )
    |> Repo.all()
  end

  @doc """
  Deletes WAF events older than the retention period.
  Returns the number of deleted records.
  """
  def prune_old_waf_events(retention_days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days * 86_400, :second)

    {count, _} =
      from(e in WafEvent, where: e.timestamp < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  ## WAF Baselines

  @doc """
  Gets WAF baselines for a project.
  """
  def get_waf_baselines(project_id) do
    from(b in WafBaseline,
      where: b.project_id == ^project_id,
      order_by: [asc: b.metric_type]
    )
    |> Repo.all()
  end

  @doc """
  Upserts a WAF baseline.
  """
  def upsert_waf_baseline(attrs) do
    %WafBaseline{}
    |> WafBaseline.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:mean, :stddev, :sample_count, :last_computed_at, :updated_at]},
      conflict_target: [:project_id, :service_id, :metric_type, :period]
    )
  end

  ## WAF Anomalies

  @doc """
  Lists WAF anomalies for a project with optional status filter.
  """
  def list_waf_anomalies(project_id, opts \\ []) do
    query =
      from(a in WafAnomaly,
        where: a.project_id == ^project_id,
        order_by: [desc: a.detected_at],
        limit: ^Keyword.get(opts, :limit, 100)
      )

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [a], a.status == ^status)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single WAF anomaly by ID.
  """
  def get_waf_anomaly(id), do: Repo.get(WafAnomaly, id)

  @doc """
  Creates a WAF anomaly.
  """
  def create_waf_anomaly(attrs) do
    %WafAnomaly{}
    |> WafAnomaly.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Acknowledges a WAF anomaly.
  """
  def acknowledge_anomaly(id, user_id) do
    case get_waf_anomaly(id) do
      nil -> {:error, :not_found}
      anomaly -> anomaly |> WafAnomaly.acknowledge_changeset(user_id) |> Repo.update()
    end
  end

  @doc """
  Resolves a WAF anomaly.
  """
  def resolve_anomaly(id) do
    case get_waf_anomaly(id) do
      nil -> {:error, :not_found}
      anomaly -> anomaly |> WafAnomaly.resolve_changeset() |> Repo.update()
    end
  end

  @doc """
  Marks a WAF anomaly as a false positive.
  """
  def mark_false_positive(id, user_id) do
    case get_waf_anomaly(id) do
      nil -> {:error, :not_found}
      anomaly -> anomaly |> WafAnomaly.false_positive_changeset(user_id) |> Repo.update()
    end
  end

  @doc """
  Returns anomaly statistics for a project.
  """
  def get_anomaly_stats(project_id) do
    stats =
      from(a in WafAnomaly,
        where: a.project_id == ^project_id,
        group_by: a.status,
        select: {a.status, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      active: Map.get(stats, "active", 0),
      acknowledged: Map.get(stats, "acknowledged", 0),
      resolved: Map.get(stats, "resolved", 0),
      false_positive: Map.get(stats, "false_positive", 0)
    }
  end

  ## Private

  defp resolve_time_range(hours) when is_integer(hours) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -hours * 3600, :second)
    {start_time, end_time}
  end

  defp resolve_time_range({start_time, end_time}), do: {start_time, end_time}

  defp parse_datetime(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime_usec(nil), do: DateTime.utc_now()

  defp parse_datetime_usec(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime_usec(%DateTime{} = dt), do: dt

  defp normalize_aggregation(nil) do
    %{
      total_requests: 0,
      total_errors: 0,
      avg_latency_p50: nil,
      avg_latency_p95: nil,
      avg_latency_p99: nil,
      total_bandwidth_in: 0,
      total_bandwidth_out: 0,
      total_2xx: 0,
      total_3xx: 0,
      total_4xx: 0,
      total_5xx: 0,
      status_2xx: 0,
      status_3xx: 0,
      status_4xx: 0,
      status_5xx: 0
    }
  end

  defp normalize_aggregation(result) when is_map(result) do
    Map.new(result, fn
      {k, nil}
      when k in [
             :total_requests,
             :total_errors,
             :total_bandwidth_in,
             :total_bandwidth_out,
             :total_2xx,
             :total_3xx,
             :total_4xx,
             :total_5xx,
             :status_2xx,
             :status_3xx,
             :status_4xx,
             :status_5xx
           ] ->
        {k, 0}

      {k, %Decimal{} = v} ->
        {k, Decimal.to_float(v) |> Float.round(1)}

      {k, v} ->
        {k, v}
    end)
  end
end
