defmodule SentinelCp.Events.DeliveryWorker do
  @moduledoc """
  Oban worker for reliable notification delivery with exponential backoff.
  Moves permanently failed deliveries to the dead-letter queue.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias SentinelCp.Repo
  alias SentinelCp.Events
  alias SentinelCp.Events.{DeliveryAttempt, Channel}
  alias SentinelCp.Events.Adapters

  require Logger

  @doc """
  Enqueues a delivery attempt for processing.
  """
  def enqueue(attempt_id) do
    %{attempt_id: attempt_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}}) do
    attempt = Repo.get(DeliveryAttempt, attempt_id) |> Repo.preload([:channel])

    if attempt && attempt.status == "pending" do
      event = Events.get_event(attempt.event_id)
      channel = attempt.channel

      if event && channel do
        execute_delivery(attempt, event, channel)
      else
        Logger.warning("Delivery attempt #{attempt_id}: missing event or channel")
        :ok
      end
    else
      :ok
    end
  end

  @max_response_body_size 10_240

  defp execute_delivery(attempt, event, channel) do
    start_time = System.monotonic_time(:millisecond)

    # Mark as delivering
    attempt
    |> Ecto.Changeset.change(%{status: "delivering"})
    |> Repo.update!()

    {result, request_body, response_body} = deliver_to_channel(event, channel)
    latency_ms = System.monotonic_time(:millisecond) - start_time
    response_body = truncate_body(response_body)

    case result do
      {:ok, http_status} ->
        attempt
        |> DeliveryAttempt.complete_changeset(%{
          status: "delivered",
          http_status: http_status,
          latency_ms: latency_ms,
          request_body: request_body,
          response_body: response_body
        })
        |> Repo.update!()

        :ok

      {:error, reason} ->
        handle_failure(attempt, reason, latency_ms, request_body, response_body)
    end
  end

  defp truncate_body(nil), do: nil

  defp truncate_body(body) when byte_size(body) > @max_response_body_size do
    String.slice(body, 0, @max_response_body_size) <> "\n... [truncated]"
  end

  defp truncate_body(body), do: body

  defp deliver_to_channel(event, %Channel{type: "slack", config: config}) do
    payload = Adapters.Slack.format_payload(event)
    request_body = Jason.encode!(payload, pretty: true)
    webhook_url = config["webhook_url"]
    result = Adapters.Slack.deliver(webhook_url, payload)
    {result, request_body, extract_response_body(result)}
  end

  defp deliver_to_channel(event, %Channel{type: "pagerduty", config: config}) do
    routing_key = config["routing_key"]
    payload = Adapters.PagerDuty.format_payload(event, routing_key)
    request_body = Jason.encode!(payload, pretty: true)
    result = Adapters.PagerDuty.deliver(routing_key, payload)
    {result, request_body, extract_response_body(result)}
  end

  defp deliver_to_channel(event, %Channel{type: "email", config: config}) do
    email_payload = Adapters.Email.format_payload(event)

    request_body =
      Jason.encode!(%{to: config["to"], subject: email_payload.subject}, pretty: true)

    to = config["to"]
    from = config["from"] || "noreply@sentinel-cp.local"
    result = Adapters.Email.deliver(to, from, email_payload.subject, email_payload.body)

    response_body =
      case result do
        {:ok, _} -> "Email queued"
        {:error, reason} -> inspect(reason)
      end

    {result, request_body, response_body}
  end

  defp deliver_to_channel(event, %Channel{type: "teams", config: config}) do
    payload = Adapters.Teams.format_payload(event)
    request_body = Jason.encode!(payload, pretty: true)
    webhook_url = config["webhook_url"]
    result = Adapters.Teams.deliver(webhook_url, payload)
    {result, request_body, extract_response_body(result)}
  end

  defp deliver_to_channel(event, %Channel{type: "webhook", config: config} = channel) do
    payload = Adapters.Webhook.format_payload(event)
    request_body = Jason.encode!(payload, pretty: true)
    url = config["url"]
    result = Adapters.Webhook.deliver(url, payload, channel.signing_secret)
    {result, request_body, extract_response_body(result)}
  end

  defp deliver_to_channel(_event, %Channel{type: type}) do
    {{:error, {:unknown_channel_type, type}}, nil, nil}
  end

  defp extract_response_body({:ok, _status}), do: nil

  defp extract_response_body({:error, {:http_error, _status, body}}) when is_binary(body),
    do: body

  defp extract_response_body({:error, {:http_error, _status, body}}),
    do: inspect(body)

  defp extract_response_body({:error, _reason}), do: nil

  defp handle_failure(attempt, reason, latency_ms, request_body, response_body) do
    error_msg = inspect(reason)

    http_status =
      case reason do
        {:http_error, status, _} -> status
        _ -> nil
      end

    if attempt.attempt_number >= DeliveryAttempt.max_retries() do
      # Move to dead-letter queue
      attempt
      |> DeliveryAttempt.complete_changeset(%{
        status: "dead_letter",
        http_status: http_status,
        latency_ms: latency_ms,
        error: error_msg,
        request_body: request_body,
        response_body: response_body
      })
      |> Repo.update!()

      Logger.warning("Delivery attempt #{attempt.id} moved to dead letter queue",
        channel_id: attempt.channel_id,
        attempt: attempt.attempt_number
      )
    else
      # Schedule retry with exponential backoff
      next_retry = DeliveryAttempt.next_retry_time(attempt.attempt_number)

      {:ok, _new_attempt} =
        attempt
        |> DeliveryAttempt.complete_changeset(%{
          status: "failed",
          http_status: http_status,
          latency_ms: latency_ms,
          error: error_msg,
          request_body: request_body,
          response_body: response_body
        })
        |> Repo.update()

      # Create new attempt for retry
      {:ok, retry_attempt} =
        %DeliveryAttempt{}
        |> DeliveryAttempt.changeset(%{
          event_id: attempt.event_id,
          channel_id: attempt.channel_id,
          status: "pending",
          attempt_number: attempt.attempt_number + 1,
          next_retry_at: next_retry
        })
        |> Repo.insert()

      # Schedule the retry with delay
      %{attempt_id: retry_attempt.id}
      |> __MODULE__.new(scheduled_at: next_retry)
      |> Oban.insert()
    end

    :ok
  end
end
