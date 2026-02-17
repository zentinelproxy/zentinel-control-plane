defmodule ZentinelCp.PromEx.ZentinelPlugin do
  @moduledoc """
  Custom PromEx plugin for Zentinel Control Plane metrics.

  Emits:
  - `zentinel_cp_bundles_total` — counter by status (compiled, failed)
  - `zentinel_cp_nodes_total` — gauge by status (online, offline)
  - `zentinel_cp_rollouts_active` — gauge of running rollouts
  - `zentinel_cp_webhook_events_total` — counter by event type
  - `zentinel_cp_drift_events_active` — gauge of unresolved drift events
  - `zentinel_cp_drift_nodes_drifted` — gauge of currently drifted nodes
  - `zentinel_cp_drift_events_total` — counter by type (detected, resolved)
  """
  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :zentinel_cp_polling_metrics,
      poll_rate,
      {__MODULE__, :poll_metrics, []},
      [
        last_value(
          [:zentinel_cp, :nodes, :total],
          event_name: [:zentinel_cp, :nodes, :count],
          description: "Total number of nodes by status",
          measurement: :count,
          tags: [:status]
        ),
        last_value(
          [:zentinel_cp, :rollouts, :active],
          event_name: [:zentinel_cp, :rollouts, :active_count],
          description: "Number of currently active rollouts",
          measurement: :count
        ),
        last_value(
          [:zentinel_cp, :drift, :events, :active],
          event_name: [:zentinel_cp, :drift, :events, :active_count],
          description: "Number of unresolved drift events",
          measurement: :count
        ),
        last_value(
          [:zentinel_cp, :drift, :nodes, :drifted],
          event_name: [:zentinel_cp, :drift, :nodes, :drifted_count],
          description: "Number of currently drifted nodes",
          measurement: :count
        ),
        last_value(
          [:zentinel_cp, :slos, :total],
          event_name: [:zentinel_cp, :slos, :status_count],
          description: "Total number of SLOs by status",
          measurement: :count,
          tags: [:status]
        ),
        last_value(
          [:zentinel_cp, :alerts, :firing],
          event_name: [:zentinel_cp, :alerts, :firing_count],
          description: "Number of currently firing alerts",
          measurement: :count
        )
      ]
    )
  end

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :zentinel_cp_event_metrics,
      [
        counter(
          [:zentinel_cp, :bundles, :total],
          event_name: [:zentinel_cp, :bundles, :created],
          description: "Total bundles created by status",
          measurement: :count,
          tags: [:status]
        ),
        counter(
          [:zentinel_cp, :webhook, :events, :total],
          event_name: [:zentinel_cp, :webhook, :received],
          description: "Total webhook events received by type",
          measurement: :count,
          tags: [:event_type]
        ),
        counter(
          [:zentinel_cp, :drift, :events, :total],
          event_name: [:zentinel_cp, :drift, :event],
          description: "Total drift events by type",
          measurement: :count,
          tags: [:type]
        )
      ]
    )
  end

  @doc false
  def poll_metrics do
    # Node counts by status
    for status <- ["online", "offline", "unknown"] do
      count = poll_node_count(status)

      :telemetry.execute(
        [:zentinel_cp, :nodes, :count],
        %{count: count},
        %{status: status}
      )
    end

    # Active rollouts
    active_rollouts = poll_active_rollouts()

    :telemetry.execute(
      [:zentinel_cp, :rollouts, :active_count],
      %{count: active_rollouts},
      %{}
    )

    # Active drift events
    active_drift_events = poll_active_drift_events()

    :telemetry.execute(
      [:zentinel_cp, :drift, :events, :active_count],
      %{count: active_drift_events},
      %{}
    )

    # Drifted nodes
    drifted_nodes = poll_drifted_nodes()

    :telemetry.execute(
      [:zentinel_cp, :drift, :nodes, :drifted_count],
      %{count: drifted_nodes},
      %{}
    )

    # SLO status counts
    for status <- ["healthy", "warning", "breached"] do
      count = poll_slo_count(status)

      :telemetry.execute(
        [:zentinel_cp, :slos, :status_count],
        %{count: count},
        %{status: status}
      )
    end

    # Firing alerts
    firing_alerts = poll_firing_alerts()

    :telemetry.execute(
      [:zentinel_cp, :alerts, :firing_count],
      %{count: firing_alerts},
      %{}
    )
  end

  defp poll_node_count(status) do
    import Ecto.Query

    ZentinelCp.Repo.aggregate(
      from(n in "nodes", where: n.status == ^status),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_active_rollouts do
    import Ecto.Query

    ZentinelCp.Repo.aggregate(
      from(r in "rollouts", where: r.state in ["pending", "in_progress"]),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_active_drift_events do
    import Ecto.Query

    ZentinelCp.Repo.aggregate(
      from(d in "drift_events", where: is_nil(d.resolved_at)),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_drifted_nodes do
    import Ecto.Query

    ZentinelCp.Repo.aggregate(
      from(n in "nodes",
        where: n.status == "online",
        where: not is_nil(n.expected_bundle_id),
        where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
      ),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_slo_count(status) do
    import Ecto.Query

    budget_filter =
      case status do
        "healthy" ->
          dynamic([s], is_nil(s.error_budget_remaining) or s.error_budget_remaining >= 50.0)

        "warning" ->
          dynamic([s], s.error_budget_remaining < 50.0 and s.error_budget_remaining > 0.0)

        "breached" ->
          dynamic([s], s.error_budget_remaining <= 0.0)
      end

    ZentinelCp.Repo.aggregate(
      from(s in "slos", where: ^budget_filter),
      :count
    )
  rescue
    _ -> 0
  end

  defp poll_firing_alerts do
    import Ecto.Query

    ZentinelCp.Repo.aggregate(
      from(s in "alert_states", where: s.state == "firing"),
      :count
    )
  rescue
    _ -> 0
  end

  @doc """
  Emits a telemetry event for drift detection.
  Call this when a drift event is created.
  """
  def emit_drift_detected do
    :telemetry.execute(
      [:zentinel_cp, :drift, :event],
      %{count: 1},
      %{type: "detected"}
    )
  end

  @doc """
  Emits a telemetry event for drift resolution.
  Call this when a drift event is resolved.
  """
  def emit_drift_resolved(resolution) do
    :telemetry.execute(
      [:zentinel_cp, :drift, :event],
      %{count: 1},
      %{type: "resolved_#{resolution}"}
    )
  end
end
