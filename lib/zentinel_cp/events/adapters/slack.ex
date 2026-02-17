defmodule ZentinelCp.Events.Adapters.Slack do
  @moduledoc """
  Slack notification adapter using Block Kit message formatting.
  """

  def format_payload(event) do
    blocks = [
      %{
        type: "header",
        text: %{
          type: "plain_text",
          text: event_title(event.type),
          emoji: true
        }
      },
      %{
        type: "section",
        fields: [
          %{type: "mrkdwn", text: "*Event:*\n`#{event.type}`"},
          %{type: "mrkdwn", text: "*Time:*\n#{format_time(event.emitted_at)}"}
        ]
      },
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: format_payload_details(event.payload)
        }
      }
    ]

    %{blocks: blocks}
  end

  def deliver(webhook_url, payload) do
    body = Jason.encode!(payload)

    case Req.post(webhook_url,
           body: body,
           headers: [{"content-type", "application/json"}],
           receive_timeout: 15_000,
           pool_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, status}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp event_title(type) do
    type
    |> String.replace(".", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_time(nil), do: "N/A"
  defp format_time(dt), do: DateTime.to_iso8601(dt)

  defp format_payload_details(payload) when map_size(payload) == 0, do: "_No additional details_"

  defp format_payload_details(payload) do
    payload
    |> Enum.take(5)
    |> Enum.map(fn {k, v} -> "*#{k}:* #{inspect(v)}" end)
    |> Enum.join("\n")
  end
end
