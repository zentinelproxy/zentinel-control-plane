defmodule ZentinelCpWeb.Api.ConfigExportController do
  use ZentinelCpWeb, :controller

  alias ZentinelCp.ConfigExport

  def export(conn, params) do
    with {:ok, project_id} <- resolve_project_id(params) do
      {:ok, config} = ConfigExport.export(project_id)
      json(conn, config)
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def import(conn, params) do
    with {:ok, project_id} <- resolve_project_id(params) do
      config = Map.drop(params, ["project_id", "project_slug"])
      {:ok, summary} = ConfigExport.import_config(project_id, config)

      json(conn, %{
        status: "ok",
        created: summary.created,
        updated: summary.updated,
        skipped: summary.skipped,
        errors: length(summary.errors)
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def diff(conn, params) do
    with {:ok, project_id} <- resolve_project_id(params) do
      config = Map.drop(params, ["project_id", "project_slug"])
      {:ok, changes} = ConfigExport.diff(project_id, config)

      formatted =
        Enum.map(changes, fn {action, resource_type, name} ->
          %{action: action, resource_type: resource_type, name: name}
        end)

      json(conn, %{changes: formatted})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  defp resolve_project_id(%{"project_id" => project_id}), do: {:ok, project_id}

  defp resolve_project_id(%{"project_slug" => slug}) do
    case ZentinelCp.Projects.get_project_by_slug(slug) do
      nil -> {:error, :not_found}
      project -> {:ok, project.id}
    end
  end
end
