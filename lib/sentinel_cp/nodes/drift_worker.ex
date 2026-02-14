defmodule SentinelCp.Nodes.DriftWorker do
  @moduledoc """
  Oban worker that detects configuration drift on nodes.

  Runs periodically and checks for nodes where active_bundle_id differs from
  expected_bundle_id. Creates drift events for newly drifted nodes and
  auto-resolves events when nodes come back in sync.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30]

  require Logger

  import Ecto.Query
  alias SentinelCp.{Bundles, Nodes, Projects, Repo}
  alias SentinelCp.Events, as: Notifications
  alias SentinelCp.Bundles.Diff
  alias SentinelCp.Nodes.{DriftEvent, Node}
  alias SentinelCp.Projects.Project

  @default_check_interval_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("DriftWorker: checking for configuration drift")

    # Find all online nodes with expected_bundle_id set
    drifted_nodes = find_drifted_nodes()
    resolved_nodes = find_resolved_nodes()

    # Create drift events for newly drifted nodes
    for node <- drifted_nodes do
      case Nodes.get_active_drift_event(node.id) do
        nil ->
          create_drift_event(node)

        _existing ->
          :ok
      end
    end

    # Auto-resolve drift events for nodes that came back in sync
    for node <- resolved_nodes do
      case Nodes.get_active_drift_event(node.id) do
        nil ->
          :ok

        event ->
          {:ok, _} = Nodes.resolve_drift_event(event, "auto_corrected")
          Logger.info("DriftWorker: auto-resolved drift for node #{node.name}")
      end
    end

    # Check alert thresholds for each project
    check_alert_thresholds()

    reschedule()
    :ok
  end

  defp find_drifted_nodes do
    from(n in Node,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
    )
    |> Repo.all()
  end

  defp find_resolved_nodes do
    from(n in Node,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id == n.expected_bundle_id
    )
    |> Repo.all()
  end

  defp create_drift_event(node) do
    # Calculate diff stats and severity
    {diff_stats, severity} = calculate_drift_severity(node)

    attrs = %{
      node_id: node.id,
      project_id: node.project_id,
      expected_bundle_id: node.expected_bundle_id,
      actual_bundle_id: node.active_bundle_id,
      detected_at: DateTime.utc_now() |> DateTime.truncate(:second),
      severity: severity,
      diff_stats: diff_stats
    }

    case Nodes.create_drift_event(attrs) do
      {:ok, event} ->
        Logger.warning("DriftWorker: detected #{severity} severity drift on node #{node.name}")

        project = Projects.get_project!(node.project_id)
        Notifications.notify_drift_detected(node, event, project)

        {:ok, event}

      {:error, changeset} ->
        Logger.error("DriftWorker: failed to create drift event: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp calculate_drift_severity(node) do
    expected_bundle = Bundles.get_bundle(node.expected_bundle_id)
    actual_bundle = node.active_bundle_id && Bundles.get_bundle(node.active_bundle_id)

    cond do
      is_nil(expected_bundle) ->
        {nil, "medium"}

      is_nil(actual_bundle) ->
        {%{additions: 0, deletions: 0, unchanged: 0}, "critical"}

      true ->
        diff = Diff.config_diff(expected_bundle, actual_bundle)
        diff_stats = Diff.diff_stats(diff)
        severity = DriftEvent.calculate_severity(diff_stats, node.active_bundle_id)
        {Map.from_struct(diff_stats), severity}
    end
  rescue
    _ ->
      {nil, "medium"}
  end

  defp check_alert_thresholds do
    # Get all projects with alert thresholds configured
    projects = Projects.list_projects_with_drift_alerts()

    for project <- projects do
      check_project_alert(project)
    end
  end

  defp check_project_alert(project) do
    stats = Nodes.get_drift_stats(project.id)
    threshold_pct = Project.drift_alert_threshold(project)
    threshold_count = Project.drift_alert_node_count(project)

    should_alert =
      cond do
        # Check percentage threshold
        threshold_pct && stats.total_managed > 0 ->
          pct = stats.drifted / stats.total_managed * 100
          pct >= threshold_pct

        # Check count threshold
        threshold_count ->
          stats.drifted >= threshold_count

        true ->
          false
      end

    if should_alert do
      Notifications.notify_drift_threshold_exceeded(project, stats)
    end
  end

  defp reschedule do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      interval = get_check_interval()

      %{}
      |> __MODULE__.new(schedule_in: interval)
      |> Oban.insert()
    end
  end

  defp get_check_interval do
    Application.get_env(:sentinel_cp, :drift_check_interval, @default_check_interval_seconds)
  end

  @doc """
  Starts the drift worker if not already running.
  Called during application startup.
  """
  def ensure_started do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new()
      |> Oban.insert()
    end
  end
end
