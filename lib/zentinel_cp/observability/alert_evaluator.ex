defmodule ZentinelCp.Observability.AlertEvaluator do
  @moduledoc """
  Oban worker that periodically evaluates alert rules and manages alert state transitions.

  Runs every 30 seconds, evaluating all enabled, non-silenced alert rules.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30]

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Analytics.ServiceMetric
  alias ZentinelCp.Observability.{AlertRule, AlertState, Slo}
  alias ZentinelCp.Events

  require Logger

  @check_interval_seconds 30

  def ensure_started do
    %{}
    |> __MODULE__.new(schedule_in: @check_interval_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    rules =
      from(r in AlertRule,
        where: r.enabled == true,
        where: is_nil(r.silenced_until) or r.silenced_until < ^DateTime.utc_now()
      )
      |> Repo.all()

    Enum.each(rules, &evaluate_rule/1)

    # Reschedule
    ensure_started()
    :ok
  end

  @doc """
  Evaluates a single alert rule and transitions its state.
  """
  def evaluate_rule(rule) do
    current_value = evaluate_condition(rule)
    condition_met = check_threshold(rule.condition, current_value)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get or create the current alert state
    alert_state = get_or_create_state(rule)

    transition_state(alert_state, rule, condition_met, current_value, now)
  end

  ## Condition Evaluation

  defp evaluate_condition(%AlertRule{rule_type: "metric", condition: condition}) do
    metric_name = condition["metric"]
    service_id = condition["service_id"]
    window_minutes = condition["window_minutes"] || 5
    since = DateTime.utc_now() |> DateTime.add(-window_minutes * 60, :second)

    query =
      from(m in ServiceMetric,
        where: m.period_start >= ^since
      )

    query =
      if service_id do
        where(query, [m], m.service_id == ^service_id)
      else
        query
      end

    metrics =
      from(q in query,
        select: %{
          total_requests: sum(q.request_count),
          total_errors: sum(q.error_count),
          avg_p99: avg(q.latency_p99_ms),
          avg_p95: avg(q.latency_p95_ms),
          total_5xx: sum(q.status_5xx)
        }
      )
      |> Repo.one()

    extract_metric_value(metric_name, metrics)
  end

  defp evaluate_condition(%AlertRule{rule_type: "slo", condition: condition}) do
    slo_id = condition["slo_id"]

    case Repo.get(Slo, slo_id) do
      nil -> 0.0
      slo -> slo.burn_rate || 0.0
    end
  end

  defp evaluate_condition(%AlertRule{rule_type: "threshold", condition: condition}) do
    # Threshold rules re-use the metric evaluation
    evaluate_condition(%AlertRule{rule_type: "metric", condition: condition})
  end

  defp evaluate_condition(_), do: 0.0

  defp extract_metric_value("error_rate", metrics) do
    total = to_number(metrics.total_requests)
    errors = to_number(metrics.total_errors)
    if total > 0, do: errors / total * 100, else: 0.0
  end

  defp extract_metric_value("latency_p99", metrics), do: to_number(metrics.avg_p99)
  defp extract_metric_value("latency_p95", metrics), do: to_number(metrics.avg_p95)

  defp extract_metric_value("error_count", metrics), do: to_number(metrics.total_errors)
  defp extract_metric_value("request_count", metrics), do: to_number(metrics.total_requests)
  defp extract_metric_value("5xx_count", metrics), do: to_number(metrics.total_5xx)
  defp extract_metric_value(_, _), do: 0.0

  ## Threshold Checking

  defp check_threshold(%{"operator" => ">", "value" => threshold}, value),
    do: value > threshold

  defp check_threshold(%{"operator" => "<", "value" => threshold}, value),
    do: value < threshold

  defp check_threshold(%{"operator" => ">=", "value" => threshold}, value),
    do: value >= threshold

  defp check_threshold(%{"operator" => "<=", "value" => threshold}, value),
    do: value <= threshold

  defp check_threshold(%{"operator" => "==", "value" => threshold}, value),
    do: value == threshold

  defp check_threshold(%{"operator" => "!=", "value" => threshold}, value),
    do: value != threshold

  defp check_threshold(%{"burn_rate_threshold" => threshold}, value),
    do: value > threshold

  defp check_threshold(_, _), do: false

  ## State Machine

  defp get_or_create_state(rule) do
    fingerprint = generate_fingerprint(rule)

    case Repo.one(
           from(s in AlertState,
             where: s.alert_rule_id == ^rule.id and s.state in ["pending", "firing"],
             limit: 1
           )
         ) do
      nil ->
        %AlertState{alert_rule_id: rule.id, state: "inactive", fingerprint: fingerprint}

      state ->
        state
    end
  end

  defp transition_state(alert_state, rule, true = _condition_met, value, now) do
    case alert_state.state do
      "inactive" ->
        if rule.for_seconds > 0 do
          # Enter pending state
          %AlertState{}
          |> AlertState.changeset(%{
            alert_rule_id: rule.id,
            state: "pending",
            value: value,
            started_at: now,
            fingerprint: generate_fingerprint(rule)
          })
          |> Repo.insert()
        else
          # Fire immediately
          fire_alert(rule, value, now)
        end

      "pending" ->
        # Check if pending long enough
        elapsed = DateTime.diff(now, alert_state.started_at, :second)

        if elapsed >= rule.for_seconds do
          alert_state
          |> AlertState.changeset(%{state: "firing", firing_at: now, value: value})
          |> Repo.update()
          |> tap(fn {:ok, state} ->
            send_alert_notification(rule, value)
            publish_alert_state(state, rule)
          end)
        else
          # Still pending, update value
          alert_state
          |> AlertState.changeset(%{value: value})
          |> Repo.update()
        end

      "firing" ->
        # Already firing, update value
        alert_state
        |> AlertState.changeset(%{value: value})
        |> Repo.update()

      _ ->
        :ok
    end
  end

  defp transition_state(alert_state, _rule, false = _condition_met, _value, now) do
    case alert_state.state do
      state when state in ["pending", "firing"] ->
        alert_state
        |> AlertState.changeset(%{state: "resolved", resolved_at: now})
        |> Repo.update()
        |> tap(fn {:ok, updated} ->
          rule = Repo.get(AlertRule, updated.alert_rule_id)
          if rule, do: publish_alert_state(updated, rule)
        end)

      _ ->
        :ok
    end
  end

  defp fire_alert(rule, value, now) do
    {:ok, state} =
      %AlertState{}
      |> AlertState.changeset(%{
        alert_rule_id: rule.id,
        state: "firing",
        value: value,
        started_at: now,
        firing_at: now,
        fingerprint: generate_fingerprint(rule)
      })
      |> Repo.insert()

    send_alert_notification(rule, value)
    publish_alert_state(state, rule)
    {:ok, state}
  end

  defp publish_alert_state(alert_state, rule) do
    Absinthe.Subscription.publish(
      ZentinelCpWeb.Endpoint,
      alert_state,
      alert_state: rule.project_id
    )
  end

  defp send_alert_notification(rule, value) do
    Logger.warning("Alert firing: #{rule.name} (#{rule.severity}) — value: #{value}")

    Events.emit(
      "security.alert_fired",
      %{
        alert_rule_id: rule.id,
        name: rule.name,
        severity: rule.severity,
        value: value,
        rule_type: rule.rule_type,
        condition: rule.condition
      },
      project_id: rule.project_id
    )
  rescue
    _ -> :ok
  end

  defp generate_fingerprint(rule) do
    :crypto.hash(:sha256, "#{rule.id}:#{inspect(rule.condition)}")
    |> Base.hex_encode32(case: :lower, padding: false)
    |> binary_part(0, 16)
  end

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(nil), do: 0.0
  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(_), do: 0.0
end
