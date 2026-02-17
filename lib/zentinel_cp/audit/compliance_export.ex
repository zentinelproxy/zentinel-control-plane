defmodule ZentinelCp.Audit.ComplianceExport do
  @moduledoc """
  SIEM-compatible audit log export in multiple formats.

  ## Supported Formats
  - `cef` — Common Event Format (ArcSight)
  - `leef` — Log Event Extended Format (QRadar)
  - `json_lines` — JSON Lines (Splunk, Elastic, Datadog)
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Audit.AuditLog

  @doc """
  Exports audit logs in the specified format for a time range.
  Returns a string in the requested format.
  """
  def export(project_id, format, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 10_000)
    since = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    logs =
      from(l in AuditLog,
        where: l.project_id == ^project_id and l.inserted_at >= ^since,
        order_by: [asc: l.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    format_logs(logs, format)
  end

  @doc """
  Exports audit logs for all projects in the specified format.
  """
  def export_all(format, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 10_000)
    since = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    logs =
      from(l in AuditLog,
        where: l.inserted_at >= ^since,
        order_by: [asc: l.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    format_logs(logs, format)
  end

  ## Format implementations

  defp format_logs(logs, "cef") do
    logs
    |> Enum.map(&to_cef/1)
    |> Enum.join("\n")
  end

  defp format_logs(logs, "leef") do
    logs
    |> Enum.map(&to_leef/1)
    |> Enum.join("\n")
  end

  defp format_logs(logs, "json_lines") do
    logs
    |> Enum.map(&to_json_line/1)
    |> Enum.join("\n")
  end

  defp format_logs(_, format), do: {:error, "unsupported format: #{format}"}

  defp to_cef(log) do
    severity = cef_severity(log.action)
    timestamp = format_timestamp(log.inserted_at)
    details = encode_metadata(log.metadata)

    "CEF:0|ZentinelCP|ControlPlane|1.0|#{log.action}|#{log.action}|#{severity}|" <>
      "rt=#{timestamp} " <>
      "duid=#{log.id} " <>
      "src=#{log.actor_id || "system"} " <>
      "dst=#{log.resource_id || ""} " <>
      "cs1=#{log.project_id || ""} " <>
      "cs1Label=ProjectId " <>
      "msg=#{details}"
  end

  defp to_leef(log) do
    timestamp = format_timestamp(log.inserted_at)
    details = encode_metadata(log.metadata)

    "LEEF:2.0|ZentinelCP|ControlPlane|1.0|#{log.action}|" <>
      "devTime=#{timestamp}\t" <>
      "usrName=#{log.actor_id || "system"}\t" <>
      "src=#{log.resource_id || ""}\t" <>
      "action=#{log.action}\t" <>
      "project=#{log.project_id || ""}\t" <>
      "details=#{details}"
  end

  defp to_json_line(log) do
    %{
      timestamp: format_timestamp(log.inserted_at),
      event_id: log.id,
      action: log.action,
      actor_id: log.actor_id,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      project_id: log.project_id,
      metadata: log.metadata,
      source: "zentinel_cp"
    }
    |> Jason.encode!()
  end

  defp cef_severity(action) do
    cond do
      String.contains?(action, "delete") -> 7
      String.contains?(action, "create") -> 3
      String.contains?(action, "update") -> 3
      String.contains?(action, "rollback") -> 6
      true -> 1
    end
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_iso8601(dt) <> "Z"
  end

  defp encode_metadata(nil), do: ""

  defp encode_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" ")
  end
end
