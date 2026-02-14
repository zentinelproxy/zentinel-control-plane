defmodule SentinelCp.Events.Adapters.PagerDuty do
  @moduledoc """
  PagerDuty notification adapter using Events API v2.
  Supports trigger, resolve, and acknowledge actions.
  """

  @events_url "https://events.pagerduty.com/v2/enqueue"

  def format_payload(event, routing_key) do
    severity = event_severity(event.type)
    action = event_action(event.type)

    %{
      routing_key: routing_key,
      event_action: action,
      dedup_key: dedup_key(event),
      payload: %{
        summary: event_summary(event),
        source: "sentinel-cp",
        severity: severity,
        timestamp: DateTime.to_iso8601(event.emitted_at),
        custom_details: event.payload
      }
    }
  end

  def deliver(routing_key, payload) do
    body = Jason.encode!(payload)

    case Req.post(@events_url,
           body: body,
           headers: [{"content-type", "application/json"}],
           receive_timeout: 15_000,
           pool_timeout: 5_000
         ) do
      {:ok, %{status: 202}} -> {:ok, 202}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp event_severity(type) do
    cond do
      String.contains?(type, "failed") -> "error"
      String.contains?(type, "drift") -> "warning"
      String.contains?(type, "security") -> "critical"
      true -> "info"
    end
  end

  defp event_action(type) do
    cond do
      String.contains?(type, "resolved") -> "resolve"
      String.contains?(type, "completed") -> "resolve"
      true -> "trigger"
    end
  end

  defp dedup_key(event) do
    "sentinel-#{event.type}-#{event.project_id || "global"}"
  end

  defp event_summary(event) do
    "Sentinel CP: #{event.type}"
  end
end
