defmodule ZentinelCp.Notifications do
  @moduledoc """
  Notification delivery for rollout events.

  Sends HTTP POST webhooks to configured URLs when rollouts change state.
  """

  require Logger

  alias ZentinelCp.Nodes.{DriftEvent, Node}
  alias ZentinelCp.Projects
  alias ZentinelCp.Projects.Project
  alias ZentinelCp.Rollouts.Rollout

  @http_timeout 10_000

  @doc """
  Sends a notification about a rollout state change.

  Returns `:ok` on success or if notifications are not configured.
  Returns `{:error, reason}` on failure.
  """
  def notify_rollout_state_change(%Rollout{} = rollout, old_state, new_state) do
    project = Projects.get_project!(rollout.project_id)

    if Project.notifications_enabled?(project) do
      payload = build_rollout_payload(rollout, project, old_state, new_state)
      webhook_url = Project.notification_webhook(project)

      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  @doc """
  Sends a notification about a rollout being approved.
  """
  def notify_rollout_approved(%Rollout{} = rollout, approver) do
    project = Projects.get_project!(rollout.project_id)

    if Project.notifications_enabled?(project) do
      payload = %{
        event: "rollout.approved",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        rollout: rollout_info(rollout),
        project: project_info(project),
        approver: %{
          id: approver.id,
          email: approver.email
        }
      }

      webhook_url = Project.notification_webhook(project)
      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  @doc """
  Sends a notification about a rollout being rejected.
  """
  def notify_rollout_rejected(%Rollout{} = rollout, rejecter, comment) do
    project = Projects.get_project!(rollout.project_id)

    if Project.notifications_enabled?(project) do
      payload = %{
        event: "rollout.rejected",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        rollout: rollout_info(rollout),
        project: project_info(project),
        rejected_by: %{
          id: rejecter.id,
          email: rejecter.email
        },
        comment: comment
      }

      webhook_url = Project.notification_webhook(project)
      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  @doc """
  Sends a notification about configuration drift being detected on a node.
  """
  def notify_drift_detected(%Node{} = node, %DriftEvent{} = event, %Project{} = project) do
    if Project.notifications_enabled?(project) do
      payload = %{
        event: "node.drift_detected",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        node: node_info(node),
        project: project_info(project),
        drift: %{
          event_id: event.id,
          expected_bundle_id: event.expected_bundle_id,
          actual_bundle_id: event.actual_bundle_id,
          detected_at: DateTime.to_iso8601(event.detected_at)
        }
      }

      webhook_url = Project.notification_webhook(project)
      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  @doc """
  Sends a notification about configuration drift being resolved on a node.
  """
  def notify_drift_resolved(%Node{} = node, %DriftEvent{} = event, %Project{} = project) do
    if Project.notifications_enabled?(project) do
      payload = %{
        event: "node.drift_resolved",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        node: node_info(node),
        project: project_info(project),
        drift: %{
          event_id: event.id,
          expected_bundle_id: event.expected_bundle_id,
          actual_bundle_id: event.actual_bundle_id,
          detected_at: DateTime.to_iso8601(event.detected_at),
          resolved_at: event.resolved_at && DateTime.to_iso8601(event.resolved_at),
          resolution: event.resolution
        }
      }

      webhook_url = Project.notification_webhook(project)
      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  @doc """
  Sends a notification when drift threshold is exceeded for a project.
  """
  def notify_drift_threshold_exceeded(%Project{} = project, drift_stats) do
    if Project.notifications_enabled?(project) do
      payload = %{
        event: "project.drift_threshold_exceeded",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        project: project_info(project),
        drift_stats: %{
          total_managed: drift_stats.total_managed,
          drifted: drift_stats.drifted,
          in_sync: drift_stats.in_sync,
          percentage:
            if(drift_stats.total_managed > 0,
              do: Float.round(drift_stats.drifted / drift_stats.total_managed * 100, 2),
              else: 0.0
            )
        },
        threshold: %{
          percentage: Project.drift_alert_threshold(project),
          node_count: Project.drift_alert_node_count(project)
        }
      }

      webhook_url = Project.notification_webhook(project)
      send_webhook(webhook_url, payload)
    else
      :ok
    end
  end

  defp build_rollout_payload(rollout, project, old_state, new_state) do
    event =
      case new_state do
        "running" -> "rollout.started"
        "completed" -> "rollout.completed"
        "failed" -> "rollout.failed"
        "cancelled" -> "rollout.cancelled"
        "paused" -> "rollout.paused"
        _ -> "rollout.state_changed"
      end

    %{
      event: event,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      rollout: rollout_info(rollout),
      project: project_info(project),
      state_change: %{
        from: old_state,
        to: new_state
      }
    }
  end

  defp rollout_info(rollout) do
    %{
      id: rollout.id,
      state: rollout.state,
      bundle_id: rollout.bundle_id,
      strategy: rollout.strategy,
      batch_size: rollout.batch_size,
      target_selector: rollout.target_selector,
      scheduled_at: rollout.scheduled_at && DateTime.to_iso8601(rollout.scheduled_at),
      started_at: rollout.started_at && DateTime.to_iso8601(rollout.started_at),
      completed_at: rollout.completed_at && DateTime.to_iso8601(rollout.completed_at),
      error: rollout.error
    }
  end

  defp project_info(project) do
    %{
      id: project.id,
      name: project.name,
      slug: project.slug
    }
  end

  defp node_info(node) do
    %{
      id: node.id,
      name: node.name,
      hostname: node.hostname,
      ip: node.ip,
      status: node.status,
      active_bundle_id: node.active_bundle_id,
      expected_bundle_id: node.expected_bundle_id
    }
  end

  defp send_webhook(url, payload) do
    body = Jason.encode!(payload)
    headers = [{"content-type", "application/json"}]

    Logger.debug("Sending notification webhook", url: url, event: payload[:event])

    case do_http_post(url, body, headers) do
      {:ok, _} ->
        Logger.info("Notification sent successfully", url: url, event: payload[:event])
        :ok

      {:error, reason} ->
        Logger.warning("Notification failed",
          url: url,
          event: payload[:event],
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp do_http_post(url, body, _headers) do
    url_charlist = String.to_charlist(url)
    content_type = ~c"application/json"

    case :httpc.request(
           :post,
           {url_charlist, [], content_type, body},
           [timeout: @http_timeout],
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        {:ok, status}

      {:ok, {{_, status, _}, _, response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
