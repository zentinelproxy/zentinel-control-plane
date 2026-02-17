defmodule ZentinelCp.Events.Adapters.Teams do
  @moduledoc """
  Microsoft Teams notification adapter using Adaptive Cards.
  """

  def format_payload(event) do
    %{
      type: "message",
      attachments: [
        %{
          contentType: "application/vnd.microsoft.card.adaptive",
          content: %{
            "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: [
              %{
                type: "TextBlock",
                text: event_title(event.type),
                weight: "bolder",
                size: "medium"
              },
              %{
                type: "FactSet",
                facts:
                  [
                    %{title: "Event", value: event.type},
                    %{title: "Time", value: DateTime.to_iso8601(event.emitted_at)}
                  ] ++ payload_facts(event.payload)
              }
            ]
          }
        }
      ]
    }
  end

  def deliver(webhook_url, payload) do
    body = Jason.encode!(payload)

    case Req.post(webhook_url,
           body: body,
           headers: [{"content-type", "application/json"}],
           receive_timeout: 15_000,
           pool_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, status}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp event_title(type) do
    "Zentinel CP: " <>
      (type
       |> String.replace(".", " ")
       |> String.split(" ")
       |> Enum.map(&String.capitalize/1)
       |> Enum.join(" "))
  end

  defp payload_facts(payload) do
    payload
    |> Enum.take(5)
    |> Enum.map(fn {k, v} -> %{title: to_string(k), value: to_string(v)} end)
  end
end
