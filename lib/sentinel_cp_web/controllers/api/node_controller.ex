defmodule SentinelCpWeb.Api.NodeController do
  @moduledoc """
  API controller for node-facing endpoints.
  These endpoints are called by Sentinel nodes, not operators.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Analytics, Audit, Auth, Nodes, Projects, Rollouts}
  alias SentinelCp.Observability.Tracer

  @doc """
  POST /api/v1/projects/:project_slug/nodes/register

  Registers a new node. Returns the node_id and node_key.
  The node_key should be stored securely by the node.
  """
  def register(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- build_registration_attrs(params, project, conn),
         {:ok, node} <- Nodes.register_node(attrs) do
      Audit.log_system_action("node.registered", "node", node.id,
        project_id: project.id,
        metadata: %{name: node.name, ip: node.ip}
      )

      conn
      |> put_status(:created)
      |> json(%{
        node_id: node.id,
        node_key: node.node_key,
        poll_interval_s: 30
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/heartbeat

  Records a heartbeat from a node. Requires node authentication.
  """
  def heartbeat(conn, params) do
    node = conn.assigns.current_node

    Tracer.trace_heartbeat(node.id, fn ->
      attrs = %{
        health: params["health"] || %{},
        metrics: params["metrics"] || %{},
        active_bundle_id: params["active_bundle_id"],
        staged_bundle_id: params["staged_bundle_id"],
        version: params["version"],
        ip: params["ip"] || get_client_ip(conn),
        hostname: params["hostname"],
        metadata: params["metadata"] || %{}
      }

      case Nodes.record_heartbeat(node, attrs) do
        {:ok, updated_node} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "ok",
            node_id: updated_node.id,
            last_seen_at: updated_node.last_seen_at
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to record heartbeat: #{inspect(reason)}"})
      end
    end)
  end

  @doc """
  GET /api/v1/nodes/:node_id/bundles/latest

  Returns the latest bundle assignment for a node.
  Requires node authentication.
  """
  def latest_bundle(conn, _params) do
    node = conn.assigns.current_node

    case node.staged_bundle_id do
      nil ->
        conn
        |> put_status(:ok)
        |> json(%{no_update: true, poll_after_s: 30})

      staged_id when staged_id != node.active_bundle_id ->
        bundle = SentinelCp.Bundles.get_bundle(staged_id)

        if bundle && bundle.status == "compiled" do
          download_url =
            case SentinelCp.Bundles.Storage.presigned_url(bundle.storage_key) do
              {:ok, url} -> url
              _ -> nil
            end

          conn
          |> put_status(:ok)
          |> json(%{
            bundle_id: bundle.id,
            version: bundle.version,
            checksum: bundle.checksum,
            size_bytes: bundle.size_bytes,
            download_url: download_url,
            traffic_weight: get_traffic_weight(node),
            poll_after_s: 30
          })
        else
          conn
          |> put_status(:ok)
          |> json(%{no_update: true, poll_after_s: 30})
        end

      _ ->
        conn
        |> put_status(:ok)
        |> json(%{no_update: true, poll_after_s: 30})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/token

  Exchanges a node's static key for a JWT token.
  Requires node authentication (via static key or existing JWT).
  """
  def token(conn, _params) do
    node = conn.assigns.current_node

    case Auth.issue_node_token(node) do
      {:ok, token, expires_at} ->
        conn
        |> put_status(:ok)
        |> json(%{
          token: token,
          token_type: "Bearer",
          expires_at: DateTime.to_iso8601(expires_at),
          expires_in: DateTime.diff(expires_at, DateTime.utc_now(), :second)
        })

      {:error, :no_signing_key} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "No signing key configured for this organization. Contact your administrator."
        })

      {:error, :no_org} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Node's project is not assigned to an organization."})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to issue token: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/events

  Records events from a node. Accepts a single event or a batch.
  Requires node authentication.
  """
  def events(conn, %{"events" => events_list}) when is_list(events_list) do
    node = conn.assigns.current_node

    events_attrs =
      Enum.map(events_list, fn event ->
        %{
          node_id: node.id,
          event_type: event["event_type"],
          severity: event["severity"] || "info",
          message: event["message"],
          metadata: event["metadata"] || %{}
        }
      end)

    case Nodes.create_node_events(events_attrs) do
      {:ok, created} ->
        conn
        |> put_status(:created)
        |> json(%{status: "ok", count: length(created)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  def events(conn, %{"event_type" => _} = params) do
    node = conn.assigns.current_node

    attrs = %{
      node_id: node.id,
      event_type: params["event_type"],
      severity: params["severity"] || "info",
      message: params["message"],
      metadata: params["metadata"] || %{}
    }

    case Nodes.create_node_event(attrs) do
      {:ok, _event} ->
        conn
        |> put_status(:created)
        |> json(%{status: "ok", count: 1})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/config

  Upserts the runtime KDL config for a node.
  Requires node authentication.
  """
  def config(conn, %{"config_kdl" => config_kdl}) do
    node = conn.assigns.current_node

    case Nodes.upsert_runtime_config(node.id, config_kdl) do
      {:ok, runtime_config} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", config_hash: runtime_config.config_hash})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/metrics

  Ingests metrics and request logs from a node.
  Requires node authentication.
  """
  def metrics(conn, params) do
    node = conn.assigns.current_node
    metrics_list = params["metrics"] || []
    logs_list = params["request_logs"] || []

    # Inject node_id into each log entry
    logs_with_node =
      Enum.map(logs_list, fn log -> Map.put(log, "node_id", node.id) end)

    metrics_result =
      if metrics_list != [] do
        Analytics.ingest_metrics(metrics_list)
      else
        {:ok, 0}
      end

    logs_result =
      if logs_with_node != [] do
        Analytics.ingest_request_logs(logs_with_node)
      else
        {:ok, 0}
      end

    case {metrics_result, logs_result} do
      {{:ok, metrics_count}, {:ok, logs_count}} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", metrics_ingested: metrics_count, logs_ingested: logs_count})

      _ ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to ingest metrics"})
    end
  end

  @doc """
  POST /api/v1/nodes/:node_id/waf-events

  Ingests WAF events from a node. Accepts a list of WAF event payloads.
  Requires node authentication.
  """
  def waf_events(conn, %{"events" => events_list}) when is_list(events_list) do
    node = conn.assigns.current_node

    events_with_node =
      Enum.map(events_list, fn event ->
        event
        |> Map.put("node_id", node.id)
        |> Map.put("project_id", node.project_id)
      end)

    case Analytics.ingest_waf_events(events_with_node) do
      {:ok, count} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", events_ingested: count})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to ingest WAF events: #{inspect(reason)}"})
    end
  end

  def waf_events(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Expected 'events' list in request body"})
  end

  # Private helpers

  defp get_traffic_weight(node) do
    import Ecto.Query

    SentinelCp.Repo.one(
      from(s in Rollouts.RolloutStep,
        join: r in Rollouts.Rollout,
        on: s.rollout_id == r.id,
        where: r.state == "running",
        where: ^node.id in s.node_ids,
        where: s.state in ~w(running verifying),
        select: s.traffic_weight,
        limit: 1
      )
    )
  end

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp build_registration_attrs(params, project, conn) do
    %{
      project_id: project.id,
      name: params["name"],
      labels: params["labels"] || %{},
      capabilities: params["capabilities"] || [],
      version: params["version"],
      ip: params["ip"] || get_client_ip(conn),
      hostname: params["hostname"],
      metadata: params["metadata"] || %{}
    }
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
