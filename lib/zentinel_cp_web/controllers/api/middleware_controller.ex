defmodule ZentinelCpWeb.Api.MiddlewareController do
  @moduledoc """
  API controller for middleware management and service middleware chains.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}

  ## Middleware CRUD

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      middlewares = Services.list_middlewares(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        middlewares: Enum.map(middlewares, &middleware_to_json/1),
        total: length(middlewares)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, middleware} <- get_middleware(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{middleware: middleware_to_json(middleware)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Middleware not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, middleware} <- Services.create_middleware(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "middleware.created", "middleware", middleware.id,
        project_id: project.id,
        changes: %{name: middleware.name, middleware_type: middleware.middleware_type}
      )

      conn
      |> put_status(:created)
      |> json(%{middleware: middleware_to_json(middleware)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, middleware} <- get_middleware(id, project.id),
         {:ok, updated} <- Services.update_middleware(middleware, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "middleware.updated", "middleware", middleware.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{middleware: middleware_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Middleware not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, middleware} <- get_middleware(id, project.id),
         {:ok, _deleted} <- Services.delete_middleware(middleware) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "middleware.deleted", "middleware", middleware.id,
        project_id: project.id,
        changes: %{name: middleware.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Middleware not found"})
    end
  end

  ## Service Middleware Chain

  def service_index(conn, %{"project_slug" => project_slug, "id" => service_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id) do
      chain = Services.list_service_middlewares(service.id)

      conn
      |> put_status(:ok)
      |> json(%{
        service_middlewares: Enum.map(chain, &service_middleware_to_json/1),
        total: length(chain)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})
    end
  end

  def attach(conn, %{"project_slug" => project_slug, "id" => service_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         attrs <- %{
           service_id: service.id,
           middleware_id: params["middleware_id"],
           position: params["position"] || 0,
           enabled: Map.get(params, "enabled", true),
           config_override: params["config_override"] || %{}
         },
         {:ok, sm} <- Services.attach_middleware(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(
        api_key,
        "service_middleware.attached",
        "service_middleware",
        sm.id,
        project_id: project.id,
        changes: %{service_id: service.id, middleware_id: params["middleware_id"]}
      )

      sm = Services.get_service_middleware(sm.id)

      conn
      |> put_status(:created)
      |> json(%{service_middleware: service_middleware_to_json(sm)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update_attachment(
        conn,
        %{"project_slug" => project_slug, "id" => service_id, "middleware_id" => mw_id} = params
      ) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         sm when not is_nil(sm) <- Services.get_service_middleware_by(service.id, mw_id),
         {:ok, updated} <- Services.update_service_middleware(sm, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(
        api_key,
        "service_middleware.updated",
        "service_middleware",
        updated.id,
        project_id: project.id
      )

      updated = Services.get_service_middleware(updated.id)

      conn
      |> put_status(:ok)
      |> json(%{service_middleware: service_middleware_to_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Service middleware not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def detach(conn, %{"project_slug" => project_slug, "id" => service_id, "middleware_id" => mw_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         sm when not is_nil(sm) <- Services.get_service_middleware_by(service.id, mw_id),
         {:ok, _deleted} <- Services.detach_middleware(sm) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(
        api_key,
        "service_middleware.detached",
        "service_middleware",
        sm.id,
        project_id: project.id
      )

      send_resp(conn, :no_content, "")
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Service middleware not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})
    end
  end

  def reorder(conn, %{"project_slug" => project_slug, "id" => service_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id) do
      order = params["order"] || []
      pairs = Enum.map(order, fn item -> {item["id"], item["position"]} end)

      case Services.reorder_service_middlewares(service.id, pairs) do
        {:ok, :ok} ->
          api_key = conn.assigns.current_api_key

          Audit.log_api_key_action(api_key, "service_middleware.reordered", "service", service.id,
            project_id: project.id
          )

          chain = Services.list_service_middlewares(service.id)

          conn
          |> put_status(:ok)
          |> json(%{service_middlewares: Enum.map(chain, &service_middleware_to_json/1)})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_middleware(id, project_id) do
    case Services.get_middleware(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = middleware -> {:ok, middleware}
      _ -> {:error, :not_found}
    end
  end

  defp get_service(id, project_id) do
    case Services.get_service(id) do
      nil -> {:error, :service_not_found}
      %{project_id: ^project_id} = service -> {:ok, service}
      _ -> {:error, :service_not_found}
    end
  end

  defp middleware_to_json(middleware) do
    %{
      id: middleware.id,
      name: middleware.name,
      slug: middleware.slug,
      description: middleware.description,
      middleware_type: middleware.middleware_type,
      config: middleware.config,
      enabled: middleware.enabled,
      project_id: middleware.project_id,
      inserted_at: middleware.inserted_at,
      updated_at: middleware.updated_at
    }
  end

  defp service_middleware_to_json(sm) do
    %{
      id: sm.id,
      position: sm.position,
      enabled: sm.enabled,
      config_override: sm.config_override,
      service_id: sm.service_id,
      middleware_id: sm.middleware_id,
      middleware: middleware_to_json(sm.middleware),
      inserted_at: sm.inserted_at,
      updated_at: sm.updated_at
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
