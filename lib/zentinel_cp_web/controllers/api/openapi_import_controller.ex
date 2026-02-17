defmodule ZentinelCpWeb.Api.OpenApiImportController do
  @moduledoc """
  API controller for OpenAPI spec import operations.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}
  alias ZentinelCp.Services.OpenApiParser

  @doc """
  POST /api/v1/projects/:project_slug/openapi/preview
  Parses an OpenAPI spec and returns extracted services preview.
  """
  def preview(conn, %{"project_slug" => project_slug, "spec" => spec_content} = params) do
    with {:ok, project} <- get_project(project_slug),
         file_name <- params["file_name"] || "spec.json",
         {:ok, raw} <- OpenApiParser.decode_spec_file(spec_content, file_name),
         {:ok, parsed} <- OpenApiParser.parse(raw) do
      opts = if params["upstream_url"], do: [upstream_url: params["upstream_url"]], else: []
      services = OpenApiParser.extract_services(parsed, opts)
      auth_policies = OpenApiParser.extract_auth_policies(parsed)

      conn
      |> put_status(:ok)
      |> json(%{
        info: parsed.info,
        openapi_version: parsed.openapi_version,
        paths_count: map_size(parsed.paths),
        services: Enum.map(services, &service_preview_json/1),
        auth_policies: Enum.map(auth_policies, &auth_policy_preview_json/1),
        project_id: project.id
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, msg} when is_binary(msg) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: msg})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/openapi/import
  Full import: creates spec record, auth policies, and selected services.
  """
  def import(conn, %{"project_slug" => project_slug, "spec" => spec_content} = params) do
    with {:ok, project} <- get_project(project_slug),
         file_name <- params["file_name"] || "spec.json",
         {:ok, raw} <- OpenApiParser.decode_spec_file(spec_content, file_name),
         {:ok, parsed} <- OpenApiParser.parse(raw) do
      opts = if params["upstream_url"], do: [upstream_url: params["upstream_url"]], else: []
      all_services = OpenApiParser.extract_services(parsed, opts)
      auth_policies = OpenApiParser.extract_auth_policies(parsed)

      # Filter to selected paths if provided
      selected =
        case params["selected_paths"] do
          paths when is_list(paths) and paths != [] ->
            selected_set = MapSet.new(paths)
            Enum.filter(all_services, &MapSet.member?(selected_set, &1.openapi_path))

          _ ->
            all_services
        end

      import_auth = params["import_auth_policies"] != false

      # Create spec record
      content_for_checksum = Jason.encode!(parsed)
      checksum = :crypto.hash(:sha256, content_for_checksum) |> Base.encode16(case: :lower)

      spec_attrs = %{
        name: get_in(parsed.info, ["title"]) || file_name,
        file_name: file_name,
        openapi_version: parsed.openapi_version,
        spec_version: get_in(parsed.info, ["version"]),
        spec_data: parsed,
        checksum: checksum,
        paths_count: map_size(parsed.paths),
        project_id: project.id
      }

      with {:ok, spec} <- Services.create_openapi_spec(spec_attrs),
           {:ok, result} <-
             Services.import_from_openapi(project.id, spec.id, selected,
               import_auth_policies: import_auth,
               auth_policy_attrs: auth_policies
             ) do
        api_key = conn.assigns.current_api_key

        Audit.log_api_key_action(
          api_key,
          "openapi.imported",
          "openapi_spec",
          spec.id,
          project_id: project.id,
          changes: %{
            services_count: result.services_count,
            auth_policies_count: result.auth_policies_count
          }
        )

        conn
        |> put_status(:created)
        |> json(%{
          spec_id: spec.id,
          services_count: result.services_count,
          auth_policies_count: result.auth_policies_count,
          services: Enum.map(result.services, &imported_service_json/1)
        })
      else
        {:error, {:auth_policy_error, changeset}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Auth policy error", details: format_errors(changeset)})

        {:error, {:service_error, changeset}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Service error", details: format_errors(changeset)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: format_errors(changeset)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, msg} when is_binary(msg) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: msg})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/openapi/specs
  Lists imported OpenAPI specs for a project.
  """
  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      specs = Services.list_openapi_specs(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        specs: Enum.map(specs, &spec_to_json/1),
        total: length(specs)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/openapi/specs/:id
  Shows a single OpenAPI spec.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, _project} <- get_project(project_slug),
         spec when not is_nil(spec) <- Services.get_openapi_spec(id) do
      conn
      |> put_status(:ok)
      |> json(%{spec: spec_to_json(spec)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Spec not found"})
    end
  end

  @doc """
  DELETE /api/v1/projects/:project_slug/openapi/specs/:id
  Deletes an OpenAPI spec record.
  """
  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         spec when not is_nil(spec) <- Services.get_openapi_spec(id),
         {:ok, _} <- Services.delete_openapi_spec(spec) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "openapi.deleted", "openapi_spec", id,
        project_id: project.id,
        changes: %{name: spec.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Spec not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp service_preview_json(svc) do
    %{
      name: svc.name,
      route_path: svc.route_path,
      upstream_url: svc.upstream_url,
      openapi_path: svc.openapi_path,
      methods: svc.methods,
      description: svc[:description],
      security_refs: svc.security_refs
    }
  end

  defp auth_policy_preview_json(policy) do
    %{
      name: policy.name,
      auth_type: policy.auth_type,
      config: policy.config,
      description: policy[:description]
    }
  end

  defp imported_service_json(service) do
    %{
      id: service.id,
      name: service.name,
      route_path: service.route_path,
      upstream_url: service.upstream_url,
      openapi_path: service.openapi_path
    }
  end

  defp spec_to_json(spec) do
    %{
      id: spec.id,
      name: spec.name,
      file_name: spec.file_name,
      openapi_version: spec.openapi_version,
      spec_version: spec.spec_version,
      checksum: spec.checksum,
      paths_count: spec.paths_count,
      status: spec.status,
      project_id: spec.project_id,
      inserted_at: spec.inserted_at,
      updated_at: spec.updated_at
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
