defmodule ZentinelCpWeb.Api.DriftController do
  @moduledoc """
  API controller for drift event management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Nodes, Projects, Audit}

  @doc """
  GET /api/v1/projects/:project_slug/drift
  Lists drift events for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts =
        [limit: parse_int(params["limit"], 100)]
        |> maybe_add_status_filter(params["status"])

      events = Nodes.list_drift_events(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        drift_events: Enum.map(events, &drift_event_to_json/1),
        total: length(events)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/drift/stats
  Returns drift statistics for a project.
  """
  def stats(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      drift_stats = Nodes.get_drift_stats(project.id)
      event_stats = Nodes.get_drift_event_stats(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        total_managed: drift_stats.total_managed,
        drifted: drift_stats.drifted,
        in_sync: drift_stats.in_sync,
        active_events: event_stats.active,
        resolved_today: event_stats.resolved_today
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/drift/:id
  Shows a single drift event.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => event_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, event} <- get_drift_event(event_id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{drift_event: drift_event_to_json(event)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :drift_event_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Drift event not found"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/drift/:id/resolve
  Manually resolves a drift event.
  """
  def resolve(conn, %{"project_slug" => project_slug, "id" => event_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, event} <- get_drift_event(event_id, project.id),
         :ok <- check_not_resolved(event),
         {:ok, updated} <- Nodes.resolve_drift_event(event, "manual") do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "drift.resolved", "drift_event", event.id,
        project_id: project.id,
        changes: %{resolution: "manual"}
      )

      conn
      |> put_status(:ok)
      |> json(%{drift_event: drift_event_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :drift_event_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Drift event not found"})

      {:error, :already_resolved} ->
        conn |> put_status(:conflict) |> json(%{error: "Drift event already resolved"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/drift/resolve-all
  Resolves all active drift events for a project.
  """
  def resolve_all(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      events = Nodes.list_drift_events(project.id, include_resolved: false)

      resolved_count =
        Enum.reduce(events, 0, fn event, count ->
          case Nodes.resolve_drift_event(event, "manual") do
            {:ok, _} -> count + 1
            _ -> count
          end
        end)

      api_key = conn.assigns.current_api_key

      if resolved_count > 0 do
        Audit.log_api_key_action(api_key, "drift.bulk_resolved", "project", project.id,
          project_id: project.id,
          changes: %{resolved_count: resolved_count}
        )
      end

      conn
      |> put_status(:ok)
      |> json(%{resolved_count: resolved_count})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/drift/export
  Exports drift events in JSON or CSV format.

  Query parameters:
  - format: "json" or "csv" (default: "json")
  - since: ISO8601 datetime to filter events detected after this time
  - until: ISO8601 datetime to filter events detected before this time
  - status: "active", "resolved", or "all" (default: "all")
  """
  def export(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      format = params["format"] || "json"
      status = params["status"] || "all"

      opts =
        []
        |> maybe_add_status_filter(status)
        |> maybe_add_date_filter(:since, params["since"])
        |> maybe_add_date_filter(:until, params["until"])

      events =
        project.id
        |> Nodes.list_drift_events(opts)
        |> filter_by_date_range(params["since"], params["until"])

      case format do
        "csv" ->
          csv_content = events_to_csv(events)

          conn
          |> put_resp_content_type("text/csv")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"drift-events-#{project.slug}-#{Date.utc_today()}.csv\""
          )
          |> send_resp(200, csv_content)

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"drift-events-#{project.slug}-#{Date.utc_today()}.json\""
          )
          |> json(%{
            exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            project: %{id: project.id, name: project.name, slug: project.slug},
            total: length(events),
            drift_events: Enum.map(events, &drift_event_to_export_json/1)
          })
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_drift_event(id, project_id) do
    case Nodes.get_drift_event(id) do
      nil -> {:error, :drift_event_not_found}
      %{project_id: ^project_id} = event -> {:ok, event}
      _ -> {:error, :drift_event_not_found}
    end
  end

  defp check_not_resolved(%{resolved_at: nil}), do: :ok
  defp check_not_resolved(_), do: {:error, :already_resolved}

  defp maybe_add_status_filter(opts, "active"), do: [{:include_resolved, false} | opts]
  defp maybe_add_status_filter(opts, _), do: [{:include_resolved, true} | opts]

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

  defp drift_event_to_json(event) do
    %{
      id: event.id,
      node_id: event.node_id,
      project_id: event.project_id,
      expected_bundle_id: event.expected_bundle_id,
      actual_bundle_id: event.actual_bundle_id,
      severity: event.severity,
      detected_at: event.detected_at,
      resolved_at: event.resolved_at,
      resolution: event.resolution,
      inserted_at: event.inserted_at,
      updated_at: event.updated_at
    }
  end

  defp drift_event_to_export_json(event) do
    node = event.node

    %{
      id: event.id,
      node_id: event.node_id,
      node_name: node && node.name,
      node_hostname: node && node.hostname,
      project_id: event.project_id,
      expected_bundle_id: event.expected_bundle_id,
      actual_bundle_id: event.actual_bundle_id,
      severity: event.severity,
      diff_stats: event.diff_stats,
      detected_at: event.detected_at && DateTime.to_iso8601(event.detected_at),
      resolved_at: event.resolved_at && DateTime.to_iso8601(event.resolved_at),
      resolution: event.resolution,
      duration_seconds: calculate_duration(event),
      inserted_at: event.inserted_at && DateTime.to_iso8601(event.inserted_at)
    }
  end

  defp events_to_csv(events) do
    headers = [
      "id",
      "node_id",
      "node_name",
      "node_hostname",
      "severity",
      "expected_bundle_id",
      "actual_bundle_id",
      "detected_at",
      "resolved_at",
      "resolution",
      "duration_seconds"
    ]

    rows =
      Enum.map(events, fn event ->
        node = event.node

        [
          event.id,
          event.node_id,
          node && node.name,
          node && node.hostname,
          event.severity,
          event.expected_bundle_id,
          event.actual_bundle_id,
          event.detected_at && DateTime.to_iso8601(event.detected_at),
          event.resolved_at && DateTime.to_iso8601(event.resolved_at),
          event.resolution,
          calculate_duration(event)
        ]
      end)

    [headers | rows]
    |> Enum.map(&csv_row/1)
    |> Enum.join("\n")
  end

  defp csv_row(cells) do
    cells
    |> Enum.map(&csv_escape/1)
    |> Enum.join(",")
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"#{String.replace(val, "\"", "\"\"")}\""
    else
      val
    end
  end

  defp csv_escape(val), do: to_string(val)

  defp calculate_duration(%{detected_at: detected, resolved_at: resolved})
       when not is_nil(detected) and not is_nil(resolved) do
    DateTime.diff(resolved, detected)
  end

  defp calculate_duration(_), do: nil

  defp maybe_add_date_filter(opts, _key, nil), do: opts
  defp maybe_add_date_filter(opts, _key, ""), do: opts

  defp maybe_add_date_filter(opts, key, value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> [{key, dt} | opts]
      _ -> opts
    end
  end

  defp filter_by_date_range(events, since, until_dt) do
    events
    |> filter_since(since)
    |> filter_until(until_dt)
  end

  defp filter_since(events, nil), do: events
  defp filter_since(events, ""), do: events

  defp filter_since(events, since) do
    case DateTime.from_iso8601(since) do
      {:ok, dt, _} ->
        Enum.filter(events, fn e ->
          DateTime.compare(e.detected_at, dt) in [:gt, :eq]
        end)

      _ ->
        events
    end
  end

  defp filter_until(events, nil), do: events
  defp filter_until(events, ""), do: events

  defp filter_until(events, until_dt) do
    case DateTime.from_iso8601(until_dt) do
      {:ok, dt, _} ->
        Enum.filter(events, fn e ->
          DateTime.compare(e.detected_at, dt) in [:lt, :eq]
        end)

      _ ->
        events
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
