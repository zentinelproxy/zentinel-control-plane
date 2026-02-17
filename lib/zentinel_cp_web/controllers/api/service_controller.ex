defmodule ZentinelCpWeb.Api.ServiceController do
  @moduledoc """
  API controller for service management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}
  alias ZentinelCp.Services.BundleIntegration

  @doc """
  GET /api/v1/projects/:project_slug/services
  Lists services for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts =
        if params["enabled"] do
          [enabled: params["enabled"] == "true"]
        else
          []
        end

      services = Services.list_services(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        services: Enum.map(services, &service_to_json/1),
        total: length(services)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/services/:id
  Shows service details.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{service: service_to_json(service)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/services
  Creates a new service.
  """
  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, service} <- Services.create_service(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service.created", "service", service.id,
        project_id: project.id,
        changes: %{name: service.name, route_path: service.route_path}
      )

      conn
      |> put_status(:created)
      |> json(%{service: service_to_json(service)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/v1/projects/:project_slug/services/:id
  Updates an existing service.
  """
  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(id, project.id),
         {:ok, updated} <- Services.update_service(service, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service.updated", "service", service.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{service: service_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/projects/:project_slug/services/:id
  Deletes a service.
  """
  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(id, project.id),
         {:ok, _deleted} <- Services.delete_service(service) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service.deleted", "service", service.id,
        project_id: project.id,
        changes: %{name: service.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/services/preview-kdl
  Previews the generated KDL configuration.
  """
  def preview_kdl(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, kdl} <- BundleIntegration.preview_kdl(project.id) do
      conn
      |> put_status(:ok)
      |> json(%{kdl: kdl})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :no_services} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No enabled services found for this project"})
    end
  end

  @doc """
  PUT /api/v1/projects/:project_slug/services/reorder
  Reorders services by position.
  """
  def reorder(conn, %{"project_slug" => project_slug, "service_ids" => service_ids})
      when is_list(service_ids) do
    with {:ok, project} <- get_project(project_slug) do
      id_position_pairs =
        service_ids
        |> Enum.with_index()
        |> Enum.map(fn {id, idx} -> {id, idx} end)

      case Services.reorder_services(project.id, id_position_pairs) do
        {:ok, _} ->
          api_key = conn.assigns.current_api_key

          Audit.log_api_key_action(api_key, "services.reordered", "project", project.id,
            project_id: project.id,
            changes: %{service_ids: service_ids}
          )

          conn
          |> put_status(:ok)
          |> json(%{ok: true})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def reorder(conn, %{"project_slug" => _project_slug}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "service_ids must be a list"})
  end

  @doc """
  POST /api/v1/projects/:project_slug/services/generate-bundle
  Generates a bundle from the project's service definitions.
  """
  def generate_bundle(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         version <- params["version"],
         :ok <- validate_version(version),
         created_by_id <-
           conn.assigns[:current_api_key] && conn.assigns.current_api_key.user_id,
         {:ok, bundle} <-
           BundleIntegration.create_bundle_from_services(project.id, version,
             created_by_id: created_by_id
           ) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(
        api_key,
        "bundle.created_from_services",
        "bundle",
        bundle.id,
        project_id: project.id,
        changes: %{version: version}
      )

      conn
      |> put_status(:created)
      |> json(%{
        bundle: %{
          id: bundle.id,
          version: bundle.version,
          status: bundle.status,
          project_id: project.id
        }
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :no_services} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No enabled services found for this project"})

      {:error, :version_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "version is required"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_service(id, project_id) do
    case Services.get_service(id) do
      nil -> {:error, :service_not_found}
      %{project_id: ^project_id} = service -> {:ok, service}
      _ -> {:error, :service_not_found}
    end
  end

  defp validate_version(nil), do: {:error, :version_required}
  defp validate_version(""), do: {:error, :version_required}
  defp validate_version(_version), do: :ok

  defp service_to_json(service) do
    %{
      id: service.id,
      name: service.name,
      slug: service.slug,
      description: service.description,
      enabled: service.enabled,
      position: service.position,
      route_path: service.route_path,
      upstream_url: service.upstream_url,
      respond_status: service.respond_status,
      respond_body: service.respond_body,
      timeout_seconds: service.timeout_seconds,
      retry: service.retry,
      cache: service.cache,
      rate_limit: service.rate_limit,
      health_check: service.health_check,
      headers: service.headers,
      cors: service.cors,
      access_control: service.access_control,
      compression: service.compression,
      path_rewrite: service.path_rewrite,
      security: service.security,
      request_transform: service.request_transform,
      response_transform: service.response_transform,
      traffic_split: service.traffic_split,
      redirect_url: service.redirect_url,
      upstream_group_id: service.upstream_group_id,
      certificate_id: service.certificate_id,
      auth_policy_id: service.auth_policy_id,
      project_id: service.project_id,
      inserted_at: service.inserted_at,
      updated_at: service.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
