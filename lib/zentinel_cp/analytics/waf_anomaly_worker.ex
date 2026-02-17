defmodule ZentinelCp.Analytics.WafAnomalyWorker do
  @moduledoc """
  Oban worker that runs WAF anomaly detection.

  Runs every 15 minutes, loads baselines, queries the current window,
  runs the detector, and inserts anomalies. Deduplicates by checking
  for existing active anomalies of the same type within the last hour.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 900]

  require Logger

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics
  alias ZentinelCp.Analytics.{WafEvent, WafBaseline, WafAnomaly, WafAnomalyDetector}

  @check_interval_seconds 900
  @window_minutes 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    window_start = DateTime.add(now, -@window_minutes * 60, :second)

    # Get all projects with baselines
    project_ids =
      from(b in WafBaseline, distinct: true, select: b.project_id)
      |> Repo.all()

    total_anomalies =
      Enum.reduce(project_ids, 0, fn project_id, acc ->
        count = detect_for_project(project_id, window_start, now)
        acc + count
      end)

    if total_anomalies > 0 do
      Logger.info(
        "WafAnomalyWorker: detected #{total_anomalies} anomalies across #{length(project_ids)} projects"
      )
    end

    schedule_next()
    :ok
  end

  defp detect_for_project(project_id, window_start, now) do
    # Load baselines
    baselines =
      from(b in WafBaseline,
        where: b.project_id == ^project_id,
        where: is_nil(b.service_id)
      )
      |> Repo.all()
      |> Map.new(fn b -> {b.metric_type, %{mean: b.mean, stddev: b.stddev}} end)

    # Query current window observations
    observations = compute_observations(project_id, window_start, now)

    # Run spike detection
    anomalies = WafAnomalyDetector.detect(baselines, observations)

    # Detect new vectors
    known_rule_types = get_known_rule_types(project_id, window_start)
    current_rule_types = get_current_rule_types(project_id, window_start, now)
    new_vectors = WafAnomalyDetector.detect_new_vectors(known_rule_types, current_rule_types)

    all_anomalies = anomalies ++ new_vectors

    # Insert with deduplication
    inserted =
      Enum.count(all_anomalies, fn anomaly_attrs ->
        unless active_duplicate?(project_id, anomaly_attrs.anomaly_type, now) do
          attrs =
            Map.merge(anomaly_attrs, %{
              project_id: project_id,
              detected_at: DateTime.truncate(now, :second)
            })

          case Analytics.create_waf_anomaly(attrs) do
            {:ok, anomaly} ->
              ZentinelCp.Events.emit(
                "security.waf_anomaly",
                %{
                  anomaly_id: anomaly.id,
                  anomaly_type: anomaly.anomaly_type,
                  severity: anomaly.severity,
                  description: anomaly.description
                },
                project_id: project_id
              )

              true

            {:error, _} ->
              false
          end
        else
          false
        end
      end)

    inserted
  end

  defp compute_observations(project_id, window_start, _now) do
    # Total blocks in window
    total_blocks =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.action == "blocked",
        where: e.timestamp >= ^window_start,
        select: count(e.id)
      )
      |> Repo.one() || 0

    # Unique IPs in window
    unique_ips =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.timestamp >= ^window_start,
        where: not is_nil(e.client_ip),
        select: count(e.client_ip, :distinct)
      )
      |> Repo.one() || 0

    # Block rate
    total_events =
      from(e in WafEvent,
        where: e.project_id == ^project_id,
        where: e.timestamp >= ^window_start,
        select: count(e.id)
      )
      |> Repo.one() || 0

    block_rate = if total_events > 0, do: total_blocks / total_events * 100.0, else: 0.0

    %{
      "total_blocks" => total_blocks * 1.0,
      "unique_ips" => unique_ips * 1.0,
      "block_rate" => block_rate
    }
  end

  defp get_known_rule_types(project_id, cutoff) do
    # Rule types seen before the current window
    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.timestamp < ^cutoff,
      distinct: true,
      select: e.rule_type
    )
    |> Repo.all()
  end

  defp get_current_rule_types(project_id, window_start, _now) do
    from(e in WafEvent,
      where: e.project_id == ^project_id,
      where: e.timestamp >= ^window_start,
      distinct: true,
      select: e.rule_type
    )
    |> Repo.all()
  end

  defp active_duplicate?(project_id, anomaly_type, now) do
    one_hour_ago = DateTime.add(now, -3600, :second)

    from(a in WafAnomaly,
      where: a.project_id == ^project_id,
      where: a.anomaly_type == ^anomaly_type,
      where: a.status == "active",
      where: a.detected_at >= ^one_hour_ago,
      select: count(a.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @doc """
  Ensures the anomaly worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 180) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
