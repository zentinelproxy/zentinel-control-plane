defmodule ZentinelCpWeb.Api.SbomController do
  @moduledoc """
  API controller for SBOM (Software Bill of Materials) downloads.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Bundles, Projects}
  alias ZentinelCp.Bundles.Sbom

  @doc """
  GET /api/v1/projects/:project_slug/bundles/:id/sbom

  Returns the CycloneDX SBOM for a bundle.
  Generates on-the-fly if not cached on the bundle.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => bundle_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, bundle} <- get_bundle(bundle_id, project.id) do
      sbom = get_or_generate_sbom(bundle)

      case sbom do
        {:ok, sbom_data} ->
          conn
          |> put_resp_content_type(Sbom.content_type())
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"sbom-#{bundle.version}.json\""
          )
          |> json(sbom_data)

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to generate SBOM: #{inspect(reason)}"})
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp get_bundle(id, project_id) do
    case Bundles.get_bundle(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = bundle -> {:ok, bundle}
      _ -> {:error, :not_found}
    end
  end

  defp get_or_generate_sbom(%{sbom: sbom}) when is_map(sbom) and map_size(sbom) > 0 do
    {:ok, sbom}
  end

  defp get_or_generate_sbom(bundle) do
    case Sbom.generate(bundle) do
      {:ok, sbom} ->
        # Cache the SBOM on the bundle
        Bundles.update_bundle_sbom(bundle, sbom)
        {:ok, sbom}

      error ->
        error
    end
  end
end
