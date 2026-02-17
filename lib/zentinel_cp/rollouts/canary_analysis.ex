defmodule ZentinelCp.Rollouts.CanaryAnalysis do
  @moduledoc """
  Statistical canary analysis comparing canary vs baseline node metrics.

  Supports:
  - Threshold-based comparison (error rate, latency)
  - Progressive traffic increase with analysis at each step
  - Automatic rollback when canary metrics degrade beyond threshold
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.RequestLog

  @default_config %{
    "error_rate_threshold" => 5.0,
    "latency_p99_threshold_ms" => 500,
    "analysis_window_minutes" => 5,
    "confidence_level" => 0.95,
    "steps" => [5, 25, 50, 100]
  }

  @doc """
  Performs canary analysis comparing canary nodes against baseline nodes.
  Returns `{:promote | :rollback | :extend, analysis_result}`.
  """
  def analyze(rollout, canary_node_ids, baseline_node_ids) do
    config = Map.merge(@default_config, rollout.canary_analysis_config || %{})
    window_minutes = config["analysis_window_minutes"]
    since = DateTime.utc_now() |> DateTime.add(-window_minutes * 60, :second)

    canary_metrics = aggregate_metrics(canary_node_ids, since)
    baseline_metrics = aggregate_metrics(baseline_node_ids, since)

    result = %{
      canary: canary_metrics,
      baseline: baseline_metrics,
      analyzed_at: DateTime.utc_now(),
      window_minutes: window_minutes
    }

    decision = make_decision(canary_metrics, baseline_metrics, config)
    {decision, Map.put(result, :decision, decision)}
  end

  @doc """
  Returns the current canary step percentage based on the analysis config and step index.
  """
  def current_step_percentage(config, step_index) do
    steps = (config || @default_config)["steps"] || [5, 25, 50, 100]
    Enum.at(steps, step_index, 100)
  end

  @doc """
  Determines if there's a next step after the current one.
  """
  def next_step?(config, step_index) do
    steps = (config || @default_config)["steps"] || [5, 25, 50, 100]
    step_index + 1 < length(steps)
  end

  @doc """
  Returns the default canary analysis configuration.
  """
  def default_config, do: @default_config

  ## Private

  defp aggregate_metrics(node_ids, since) when is_list(node_ids) and node_ids != [] do
    query =
      from(r in RequestLog,
        where: r.node_id in ^node_ids and r.timestamp >= ^since,
        select: %{
          total_requests: count(r.id),
          total_errors: fragment("SUM(CASE WHEN ? >= 500 THEN 1 ELSE 0 END)", r.status),
          avg_latency_p99: avg(r.latency_ms)
        }
      )

    case Repo.one(query) do
      nil ->
        %{total_requests: 0, total_errors: 0, avg_latency_p99: 0, error_rate: 0.0}

      metrics ->
        total = metrics.total_requests || 0
        errors = metrics.total_errors || 0

        error_rate =
          if total > 0 do
            errors / total * 100
          else
            0.0
          end

        %{
          total_requests: total,
          total_errors: errors,
          avg_latency_p99: metrics.avg_latency_p99 || 0,
          error_rate: error_rate
        }
    end
  end

  defp aggregate_metrics(_, _),
    do: %{total_requests: 0, total_errors: 0, avg_latency_p99: 0, error_rate: 0.0}

  defp make_decision(canary, baseline, config) do
    error_threshold = config["error_rate_threshold"]
    latency_threshold = config["latency_p99_threshold_ms"]

    cond do
      # Not enough data — extend observation
      canary.total_requests < 10 ->
        :extend

      # Canary error rate exceeds absolute threshold
      canary.error_rate > error_threshold ->
        :rollback

      # Canary latency exceeds absolute threshold
      canary.avg_latency_p99 > latency_threshold ->
        :rollback

      # Canary error rate significantly worse than baseline (2x)
      baseline.total_requests > 10 and canary.error_rate > baseline.error_rate * 2 ->
        :rollback

      # Canary latency significantly worse than baseline (1.5x)
      baseline.total_requests > 10 and canary.avg_latency_p99 > baseline.avg_latency_p99 * 1.5 ->
        :rollback

      # All looks good — promote to next step
      true ->
        :promote
    end
  end
end
