defmodule ZentinelCp.Dashboard do
  @moduledoc """
  The Dashboard context provides aggregated metrics and overview data.
  Read-only queries over existing data.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Nodes
  alias ZentinelCp.Nodes.Node
  alias ZentinelCp.Bundles.Bundle
  alias ZentinelCp.Rollouts.Rollout
  alias ZentinelCp.Projects.Project
  alias ZentinelCp.Audit.AuditLog

  @doc """
  Returns an overview of an org's fleet.
  """
  def get_org_overview(org_id) do
    projects = list_org_projects(org_id)
    project_ids = Enum.map(projects, & &1.id)

    %{
      project_count: length(projects),
      node_stats: get_fleet_node_stats(project_ids),
      drift_stats: Nodes.get_fleet_drift_stats(project_ids),
      drift_event_stats: Nodes.get_fleet_drift_event_stats(project_ids),
      active_rollouts: count_active_rollouts(project_ids),
      recent_bundles: count_recent_bundles(project_ids, 7),
      deployment_success_rate: deployment_success_rate(project_ids),
      circuit_breaker_summary: get_fleet_circuit_breaker_summary(project_ids),
      waf_anomaly_count: count_active_waf_anomalies(project_ids)
    }
  end

  @doc """
  Returns overview for a single project.
  """
  def get_project_overview(project_id) do
    alias ZentinelCp.Observability

    %{
      node_stats: get_project_node_stats(project_id),
      active_rollouts: count_active_rollouts([project_id]),
      recent_bundles: count_recent_bundles([project_id], 7),
      latest_bundles: list_latest_bundles(project_id, 5),
      latest_rollouts: list_latest_rollouts(project_id, 5),
      slo_summary: Observability.slo_summary(project_id),
      firing_alert_count: Observability.firing_alert_count(project_id)
    }
  end

  @doc """
  Returns recent activity for an org.
  """
  def get_recent_activity(org_id, limit \\ 20) do
    from(a in AuditLog,
      where: a.org_id == ^org_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns fleet-wide node status counts across all given projects.
  """
  def get_fleet_node_stats(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{total: 0, online: 0, offline: 0, unknown: 0}
    else
      stats =
        from(n in Node,
          where: n.project_id in ^project_ids,
          group_by: n.status,
          select: {n.status, count(n.id)}
        )
        |> Repo.all()
        |> Map.new()

      %{
        total: Map.values(stats) |> Enum.sum(),
        online: Map.get(stats, "online", 0),
        offline: Map.get(stats, "offline", 0),
        unknown: Map.get(stats, "unknown", 0)
      }
    end
  end

  @doc """
  Returns node stats for a single project.
  """
  def get_project_node_stats(project_id) do
    get_fleet_node_stats([project_id])
  end

  @doc """
  Returns circuit breaker summary across multiple projects.
  """
  def get_fleet_circuit_breaker_summary(project_ids) when project_ids == [] do
    %{total_groups: 0, open: 0, half_open: 0, closed: 0}
  end

  def get_fleet_circuit_breaker_summary(project_ids) do
    alias ZentinelCp.Services.{CircuitBreakerStatus, UpstreamGroup}

    stats =
      from(cb in CircuitBreakerStatus,
        join: g in UpstreamGroup,
        on: g.id == cb.upstream_group_id,
        where: g.project_id in ^project_ids,
        group_by: cb.state,
        select: {cb.state, count(cb.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      total_groups: Enum.sum(Map.values(stats)),
      open: Map.get(stats, "open", 0),
      half_open: Map.get(stats, "half_open", 0),
      closed: Map.get(stats, "closed", 0)
    }
  end

  @doc """
  Counts active WAF anomalies across multiple projects.
  """
  def count_active_waf_anomalies(project_ids) when project_ids == [], do: 0

  def count_active_waf_anomalies(project_ids) do
    alias ZentinelCp.Analytics.WafAnomaly

    from(a in WafAnomaly,
      where: a.project_id in ^project_ids,
      where: a.status == "active",
      select: count(a.id)
    )
    |> Repo.one()
  end

  ## Private Helpers

  defp list_org_projects(org_id) do
    from(p in Project, where: p.org_id == ^org_id)
    |> Repo.all()
  end

  defp count_active_rollouts(project_ids) when project_ids == [], do: 0

  defp count_active_rollouts(project_ids) do
    from(r in Rollout,
      where: r.project_id in ^project_ids,
      where: r.state in ^~w(pending running paused),
      select: count(r.id)
    )
    |> Repo.one()
  end

  defp count_recent_bundles(project_ids, _days) when project_ids == [], do: 0

  defp count_recent_bundles(project_ids, days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(b in Bundle,
      where: b.project_id in ^project_ids,
      where: b.inserted_at >= ^cutoff,
      select: count(b.id)
    )
    |> Repo.one()
  end

  defp deployment_success_rate(project_ids) when project_ids == [], do: nil

  defp deployment_success_rate(project_ids) do
    totals =
      from(r in Rollout,
        where: r.project_id in ^project_ids,
        where: r.state in ^~w(completed failed cancelled),
        group_by: r.state,
        select: {r.state, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    completed = Map.get(totals, "completed", 0)
    total = Map.values(totals) |> Enum.sum()

    if total > 0, do: Float.round(completed / total * 100, 1), else: nil
  end

  defp list_latest_bundles(project_id, limit) do
    from(b in Bundle,
      where: b.project_id == ^project_id,
      order_by: [desc: b.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp list_latest_rollouts(project_id, limit) do
    from(r in Rollout,
      where: r.project_id == ^project_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
