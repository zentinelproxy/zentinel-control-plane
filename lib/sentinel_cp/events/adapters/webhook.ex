defmodule SentinelCp.Events.Adapters.Webhook do
  @moduledoc """
  Generic webhook notification adapter with HMAC signing.
  """

  def format_payload(event) do
    %{
      event: event.type,
      timestamp: DateTime.to_iso8601(event.emitted_at),
      payload: event.payload,
      project_id: event.project_id,
      org_id: event.org_id
    }
  end

  def deliver(url, payload, signing_secret \\ nil) do
    body = Jason.encode!(payload)
    headers = build_headers(body, signing_secret)

    case Req.post(url,
           body: body,
           headers: headers,
           receive_timeout: 15_000,
           pool_timeout: 5_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, status}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_headers(body, nil) do
    [{"content-type", "application/json"}]
  end

  defp build_headers(body, signing_secret) do
    timestamp = System.system_time(:second) |> to_string()
    signature_payload = "#{timestamp}.#{body}"

    signature =
      :crypto.mac(:hmac, :sha256, signing_secret, signature_payload)
      |> Base.encode16(case: :lower)

    [
      {"content-type", "application/json"},
      {"x-sentinel-signature", "t=#{timestamp},v1=#{signature}"},
      {"x-sentinel-timestamp", timestamp}
    ]
  end
end
