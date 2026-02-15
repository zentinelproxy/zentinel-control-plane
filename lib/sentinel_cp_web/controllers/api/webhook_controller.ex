defmodule SentinelCpWeb.Api.WebhookController do
  @moduledoc """
  Handles incoming GitHub webhooks.

  Authentication is via webhook signature verification (HMAC-SHA256),
  not the standard API key auth pipeline.
  """
  use SentinelCpWeb, :controller

  require Logger

  alias SentinelCp.Observability.Tracer
  alias SentinelCp.Webhooks

  @doc """
  POST /api/v1/webhooks/github

  Receives GitHub webhook events. Only processes `push` events.
  Other events are acknowledged with 200 OK.
  """
  def github(conn, _params) do
    Tracer.trace_webhook("github", fn ->
      with {:ok, body} <- read_raw_body(conn),
           signature when is_binary(signature) <- get_signature(conn),
           true <- Webhooks.verify_signature(body, signature) do
        event_type = get_event_type(conn)
        payload = Jason.decode!(body)

        handle_event(conn, event_type, payload)
      else
        nil ->
          conn |> put_status(:unauthorized) |> json(%{error: "Missing signature"})

        false ->
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid signature"})

        {:error, :no_body} ->
          conn |> put_status(:bad_request) |> json(%{error: "Empty request body"})
      end
    end)
  end

  defp handle_event(conn, "push", payload) do
    case Webhooks.process_github_push(payload) do
      {:ok, %{id: bundle_id}} ->
        Logger.info("Webhook created bundle", bundle_id: bundle_id)

        conn
        |> put_status(:created)
        |> json(%{status: "ok", bundle_id: bundle_id})

      {:ok, :ignored} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", message: "Push event ignored"})

      {:error, reason} ->
        Logger.error("Webhook processing failed", error: inspect(reason))

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to process push event"})
    end
  end

  defp handle_event(conn, event_type, _payload) do
    Logger.debug("Ignoring GitHub event", event_type: event_type)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok", message: "Event type '#{event_type}' ignored"})
  end

  defp read_raw_body(conn) do
    case conn.assigns[:raw_body] do
      body when is_binary(body) and byte_size(body) > 0 ->
        {:ok, body}

      _ ->
        {:error, :no_body}
    end
  end

  defp get_signature(conn) do
    Plug.Conn.get_req_header(conn, "x-hub-signature-256") |> List.first()
  end

  defp get_event_type(conn) do
    Plug.Conn.get_req_header(conn, "x-github-event") |> List.first() || "unknown"
  end
end
