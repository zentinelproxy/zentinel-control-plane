defmodule ZentinelCp.Analytics.WafBaselineWorker do
  @moduledoc """
  Oban worker that computes WAF event baselines.

  Runs hourly, queries the last 7 days of WAF events, computes mean/stddev
  per metric_type, and upserts baselines.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.{WafEvent, WafBaseline}

  @check_interval_seconds 3_600
  @lookback_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@lookback_days * 86_400, :second)

    # Get all projects with WAF events
    project_ids =
      from(e in WafEvent,
        where: e.timestamp >= ^cutoff,
        distinct: true,
        select: e.project_id
      )
      |> Repo.all()

    for project_id <- project_ids do
      compute_and_upsert_baselines(project_id, cutoff)
    end

    Logger.debug("WafBaselineWorker: computed baselines for #{length(project_ids)} projects")

    schedule_next()
    :ok
  end

  defp compute_and_upsert_baselines(project_id, cutoff) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Total blocks per hour
    hourly_blocks = compute_hourly_metric(project_id, cutoff, "blocked")

    if hourly_blocks != [] do
      {mean, stddev} = compute_stats(hourly_blocks)

      upsert_baseline(%{
        project_id: project_id,
        metric_type: "total_blocks",
        period: "hourly",
        mean: mean,
        stddev: stddev,
        sample_count: length(hourly_blocks),
        last_computed_at: now
      })
    end

    # Unique IPs per hour
    hourly_ips = compute_hourly_unique_ips(project_id, cutoff)

    if hourly_ips != [] do
      {mean, stddev} = compute_stats(hourly_ips)

      upsert_baseline(%{
        project_id: project_id,
        metric_type: "unique_ips",
        period: "hourly",
        mean: mean,
        stddev: stddev,
        sample_count: length(hourly_ips),
        last_computed_at: now
      })
    end

    # Block rate (blocks / total events) per hour
    hourly_rates = compute_hourly_block_rate(project_id, cutoff)

    if hourly_rates != [] do
      {mean, stddev} = compute_stats(hourly_rates)

      upsert_baseline(%{
        project_id: project_id,
        metric_type: "block_rate",
        period: "hourly",
        mean: mean,
        stddev: stddev,
        sample_count: length(hourly_rates),
        last_computed_at: now
      })
    end
  end

  defp compute_hourly_metric(project_id, cutoff, action) do
    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.action == ^action,
      where: e.timestamp >= ^cutoff,
      group_by: fragment("strftime('%Y-%m-%d %H', ?)", e.timestamp),
      select: count(e.id)
    )
    |> Repo.all()
    |> Enum.map(&(&1 * 1.0))
  end

  defp compute_hourly_unique_ips(project_id, cutoff) do
    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.timestamp >= ^cutoff,
      where: not is_nil(e.client_ip),
      group_by: fragment("strftime('%Y-%m-%d %H', ?)", e.timestamp),
      select: count(e.client_ip, :distinct)
    )
    |> Repo.all()
    |> Enum.map(&(&1 * 1.0))
  end

  defp compute_hourly_block_rate(project_id, cutoff) do
    # Get hourly totals and blocked counts
    hours =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.timestamp >= ^cutoff,
        group_by: fragment("strftime('%Y-%m-%d %H', ?)", e.timestamp),
        select: %{
          total: count(e.id),
          blocked: count(fragment("CASE WHEN ? = 'blocked' THEN 1 END", e.action))
        }
      )
      |> Repo.all()

    Enum.map(hours, fn %{total: total, blocked: blocked} ->
      if total > 0, do: blocked / total * 100.0, else: 0.0
    end)
  end

  defp compute_stats(values) when length(values) < 2, do: {0.0, 0.0}

  defp compute_stats(values) do
    n = length(values)
    mean = Enum.sum(values) / n

    variance =
      values
      |> Enum.map(fn v -> (v - mean) * (v - mean) end)
      |> Enum.sum()
      |> Kernel./(n - 1)

    stddev = :math.sqrt(variance)
    {Float.round(mean, 4), Float.round(stddev, 4)}
  end

  defp upsert_baseline(attrs) do
    %WafBaseline{}
    |> WafBaseline.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:mean, :stddev, :sample_count, :last_computed_at, :updated_at]},
      conflict_target: [:project_id, :service_id, :metric_type, :period]
    )
  end

  @doc """
  Ensures the baseline worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 120) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
