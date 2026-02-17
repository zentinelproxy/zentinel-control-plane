defmodule ZentinelCpWeb.AuditController do
  use ZentinelCpWeb, :controller

  alias ZentinelCp.Audit

  def export(conn, params) do
    format = params["format"] || "json"

    opts =
      []
      |> maybe_add_filter(:action, params["action"])
      |> maybe_add_filter(:resource_type, params["resource_type"])
      |> maybe_add_filter(:actor_type, params["actor_type"])

    logs = Audit.export_all_audit_logs(opts)

    case format do
      "csv" ->
        csv = logs_to_csv(logs)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", "attachment; filename=\"audit_logs.csv\"")
        |> send_resp(200, csv)

      _ ->
        json = Jason.encode!(logs, pretty: true)

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("content-disposition", "attachment; filename=\"audit_logs.json\"")
        |> send_resp(200, json)
    end
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: [{key, value} | opts]

  defp logs_to_csv(logs) do
    headers = [
      "timestamp",
      "action",
      "actor_type",
      "actor_id",
      "resource_type",
      "resource_id",
      "project_id"
    ]

    header_row = Enum.join(headers, ",")

    rows =
      Enum.map(logs, fn log ->
        [
          format_datetime(log.inserted_at),
          log.action,
          log.actor_type,
          log.actor_id || "",
          log.resource_type,
          log.resource_id || "",
          log.project_id || ""
        ]
        |> Enum.map(&escape_csv_field/1)
        |> Enum.join(",")
      end)

    [header_row | rows] |> Enum.join("\n")
  end

  defp escape_csv_field(nil), do: ""

  defp escape_csv_field(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\n"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end

  defp escape_csv_field(field), do: to_string(field)

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%SZ")
  end
end
