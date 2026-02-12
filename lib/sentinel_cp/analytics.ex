defmodule SentinelCp.Analytics do
  @moduledoc """
  The Analytics context for request-level metrics and logs.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Analytics.{ServiceMetric, RequestLog}

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
      {k, nil} when k in [:total_requests, :total_errors, :total_bandwidth_in, :total_bandwidth_out,
                           :total_2xx, :total_3xx, :total_4xx, :total_5xx,
                           :status_2xx, :status_3xx, :status_4xx, :status_5xx] ->
        {k, 0}

      {k, %Decimal{} = v} ->
        {k, Decimal.to_float(v) |> Float.round(1)}

      {k, v} ->
        {k, v}
    end)
  end
end
