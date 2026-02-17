defmodule ZentinelCp.Analytics.RollupWorker do
  @moduledoc """
  Oban worker that aggregates raw service metrics into hourly and daily rollups.

  Runs hourly. On each run:
  1. Aggregates the previous hour's raw metrics into hourly rollups
  2. At midnight UTC, aggregates the previous day's hourly rollups into daily rollups
  3. Prunes raw metrics older than the configured retention period
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.{ServiceMetric, MetricRollup}

  require Logger

  @rollup_interval_seconds 3600

  def ensure_started do
    %{}
    |> __MODULE__.new(schedule_in: @rollup_interval_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Hourly rollup for the previous hour
    hourly_result = rollup_hourly(now)
    Logger.info("Hourly rollup: #{hourly_result} records created")

    # Daily rollup at the start of a new day (within first hour)
    if now.hour == 0 do
      daily_result = rollup_daily(now)
      Logger.info("Daily rollup: #{daily_result} records created")
    end

    # Prune old raw metrics (keep configurable days, default 7)
    retention_days = Application.get_env(:zentinel_cp, :metrics_retention_days, 7)
    prune_result = prune_old_metrics(retention_days)
    Logger.debug("Pruned #{prune_result} old metric records")

    # Reschedule
    ensure_started()
    :ok
  end

  @doc """
  Aggregates raw metrics from the previous hour into hourly rollups.
  Returns the number of rollup records created.
  """
  def rollup_hourly(now \\ DateTime.utc_now()) do
    # Previous hour boundary
    hour_end = %{now | minute: 0, second: 0, microsecond: {0, 0}}
    hour_start = DateTime.add(hour_end, -3600, :second)

    aggregate_period("hourly", hour_start, hour_end)
  end

  @doc """
  Aggregates hourly rollups from the previous day into daily rollups.
  Returns the number of rollup records created.
  """
  def rollup_daily(now \\ DateTime.utc_now()) do
    # Previous day boundary
    day_end = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    day_start = DateTime.add(day_end, -86400, :second)

    aggregate_period("daily", day_start, day_end)
  end

  @doc """
  Prunes raw service_metrics older than the given number of days.
  Returns the number of deleted records.
  """
  def prune_old_metrics(retention_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days * 86400, :second)

    {count, _} =
      from(m in ServiceMetric, where: m.period_start < ^cutoff)
      |> Repo.delete_all()

    count
  end

  ## Private

  defp aggregate_period(period, period_start, period_end) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    aggregates =
      from(m in ServiceMetric,
        where: m.period_start >= ^period_start and m.period_start < ^period_end,
        group_by: [m.service_id, m.project_id],
        select: %{
          service_id: m.service_id,
          project_id: m.project_id,
          request_count: sum(m.request_count),
          error_count: sum(m.error_count),
          latency_p50_ms: fragment("CAST(AVG(?) AS INTEGER)", m.latency_p50_ms),
          latency_p95_ms: fragment("CAST(AVG(?) AS INTEGER)", m.latency_p95_ms),
          latency_p99_ms: fragment("CAST(AVG(?) AS INTEGER)", m.latency_p99_ms),
          bandwidth_in_bytes: sum(m.bandwidth_in_bytes),
          bandwidth_out_bytes: sum(m.bandwidth_out_bytes),
          status_2xx: sum(m.status_2xx),
          status_3xx: sum(m.status_3xx),
          status_4xx: sum(m.status_4xx),
          status_5xx: sum(m.status_5xx)
        }
      )
      |> Repo.all()

    entries =
      Enum.map(aggregates, fn agg ->
        %{
          id: Ecto.UUID.generate(),
          service_id: agg.service_id,
          project_id: agg.project_id,
          period: period,
          period_start: period_start,
          request_count: agg.request_count || 0,
          error_count: agg.error_count || 0,
          latency_p50_ms: agg.latency_p50_ms,
          latency_p95_ms: agg.latency_p95_ms,
          latency_p99_ms: agg.latency_p99_ms,
          bandwidth_in_bytes: agg.bandwidth_in_bytes || 0,
          bandwidth_out_bytes: agg.bandwidth_out_bytes || 0,
          status_2xx: agg.status_2xx || 0,
          status_3xx: agg.status_3xx || 0,
          status_4xx: agg.status_4xx || 0,
          status_5xx: agg.status_5xx || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    case entries do
      [] ->
        0

      entries ->
        {count, _} =
          Repo.insert_all(MetricRollup, entries,
            on_conflict: :replace_all,
            conflict_target: [:service_id, :period, :period_start]
          )

        count
    end
  end
end
