defmodule ZentinelCp.Observability.SliComputer do
  @moduledoc """
  Computes SLI values and error budgets from ServiceMetric data.

  ## Computation
  - Pulls metrics from `service_metrics` table for the SLO's window period
  - Calculates current SLI value based on SLI type
  - Computes error budget remaining and burn rate
  - Updates the SLO record with computed values
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.ServiceMetric
  alias ZentinelCp.Observability.Slo

  @doc """
  Computes the SLI for a given SLO and updates it with results.
  Returns `{:ok, updated_slo}` or `{:error, reason}`.
  """
  def compute(slo) do
    window_start = DateTime.utc_now() |> DateTime.add(-slo.window_days * 86400, :second)
    metrics = fetch_metrics(slo, window_start)

    sli_value = compute_sli(slo.sli_type, metrics)
    budget = compute_error_budget(slo.sli_type, slo.target, sli_value)
    burn_rate = compute_burn_rate(slo.sli_type, slo.target, sli_value, slo.window_days)

    slo
    |> Slo.changeset(%{
      error_budget_remaining: budget,
      burn_rate: burn_rate,
      last_computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Computes the current SLI value without updating the database.
  """
  def current_sli(slo) do
    window_start = DateTime.utc_now() |> DateTime.add(-slo.window_days * 86400, :second)
    metrics = fetch_metrics(slo, window_start)
    compute_sli(slo.sli_type, metrics)
  end

  ## Private

  defp fetch_metrics(slo, window_start) do
    query =
      from(m in ServiceMetric,
        where: m.project_id == ^slo.project_id and m.period_start >= ^window_start,
        select: %{
          total_requests: sum(m.request_count),
          total_errors: sum(m.error_count),
          avg_p95: avg(m.latency_p95_ms),
          avg_p99: avg(m.latency_p99_ms),
          total_5xx: sum(m.status_5xx),
          total_2xx: sum(m.status_2xx),
          total_3xx: sum(m.status_3xx),
          total_4xx: sum(m.status_4xx)
        }
      )

    query =
      if slo.service_id do
        where(query, [m], m.service_id == ^slo.service_id)
      else
        query
      end

    Repo.one(query) || empty_metrics()
  end

  defp empty_metrics do
    %{
      total_requests: 0,
      total_errors: 0,
      avg_p95: nil,
      avg_p99: nil,
      total_5xx: 0,
      total_2xx: 0,
      total_3xx: 0,
      total_4xx: 0
    }
  end

  defp compute_sli("availability", metrics) do
    total = (metrics.total_requests || 0) |> to_number()
    errors_5xx = (metrics.total_5xx || 0) |> to_number()

    if total > 0 do
      (1.0 - errors_5xx / total) * 100
    else
      100.0
    end
  end

  defp compute_sli("error_rate", metrics) do
    total = (metrics.total_requests || 0) |> to_number()
    errors = (metrics.total_errors || 0) |> to_number()

    if total > 0 do
      errors / total * 100
    else
      0.0
    end
  end

  defp compute_sli("latency_p99", metrics) do
    to_number(metrics.avg_p99 || 0)
  end

  defp compute_sli("latency_p95", metrics) do
    to_number(metrics.avg_p95 || 0)
  end

  defp compute_sli(_, _), do: 0.0

  defp compute_error_budget(sli_type, target, sli_value) when sli_type in ["availability"] do
    # For availability: budget = target - (100 - current)
    # e.g., target 99.9%, current 99.95% → budget = 99.9 - (100-99.95) = 99.85? No.
    # Error budget remaining = 1 - ((100 - sli_value) / (100 - target))
    allowed_errors = 100.0 - target
    actual_errors = 100.0 - sli_value

    if allowed_errors > 0 do
      remaining = 1.0 - actual_errors / allowed_errors
      Float.round(remaining * 100, 2)
    else
      0.0
    end
  end

  defp compute_error_budget("error_rate", target, sli_value) do
    # For error rate: budget = 1 - (actual_rate / target_rate)
    if target > 0 do
      remaining = 1.0 - sli_value / target
      Float.round(remaining * 100, 2)
    else
      0.0
    end
  end

  defp compute_error_budget(sli_type, target, sli_value)
       when sli_type in ["latency_p99", "latency_p95"] do
    # For latency: budget = 1 - (actual / target)
    if target > 0 do
      remaining = 1.0 - sli_value / target
      Float.round(remaining * 100, 2)
    else
      0.0
    end
  end

  defp compute_error_budget(_, _, _), do: 0.0

  defp compute_burn_rate(sli_type, target, sli_value, window_days)
       when sli_type in ["availability"] do
    # Burn rate = rate at which error budget is being consumed
    # burn_rate = (error_rate_observed) / (error_rate_allowed)
    allowed = 100.0 - target
    actual = 100.0 - sli_value

    if allowed > 0 and window_days > 0 do
      Float.round(actual / allowed, 4)
    else
      0.0
    end
  end

  defp compute_burn_rate("error_rate", target, sli_value, _window_days) do
    if target > 0 do
      Float.round(sli_value / target, 4)
    else
      0.0
    end
  end

  defp compute_burn_rate(_sli_type, target, sli_value, _window_days) do
    if target > 0 do
      Float.round(sli_value / target, 4)
    else
      0.0
    end
  end

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(_), do: 0.0
end
