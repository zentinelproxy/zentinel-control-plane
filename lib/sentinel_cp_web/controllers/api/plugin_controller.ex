defmodule SentinelCpWeb.Api.PluginController do
  @moduledoc """
  API controller for plugin management, versioning, and service plugin chains.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Plugins, Projects, Services, Audit}

  ## Plugin CRUD

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      plugins = Plugins.list_plugins(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        plugins: Enum.map(plugins, &plugin_to_json/1),
        total: length(plugins)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{plugin: plugin_to_json(plugin)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, plugin} <- Plugins.create_plugin(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "plugin.created", "plugin", plugin.id,
        project_id: project.id,
        changes: %{name: plugin.name, plugin_type: plugin.plugin_type}
      )

      conn
      |> put_status(:created)
      |> json(%{plugin: plugin_to_json(plugin)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(id, project.id),
         {:ok, updated} <- Plugins.update_plugin(plugin, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "plugin.updated", "plugin", plugin.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{plugin: plugin_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(id, project.id),
         {:ok, _deleted} <- Plugins.delete_plugin(plugin) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "plugin.deleted", "plugin", plugin.id,
        project_id: project.id,
        changes: %{name: plugin.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})
    end
  end

  ## Plugin Versions

  def list_versions(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(id, project.id) do
      versions = Plugins.list_plugin_versions(plugin.id)

      conn
      |> put_status(:ok)
      |> json(%{
        versions: Enum.map(versions, &version_to_json/1),
        total: length(versions)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})
    end
  end

  def upload_version(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(id, project.id),
         {:ok, binary} <- decode_binary(params["binary"]),
         {:ok, version} <- Plugins.create_plugin_version(plugin, binary, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "plugin_version.uploaded", "plugin_version", version.id,
        project_id: project.id,
        changes: %{plugin_id: plugin.id, version: version.version}
      )

      conn
      |> put_status(:created)
      |> json(%{version: version_to_json(version)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})

      {:error, :invalid_base64} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid base64 binary"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete_version(conn, %{
        "project_slug" => project_slug,
        "id" => plugin_id,
        "vid" => version_id
      }) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, plugin} <- get_plugin(plugin_id, project.id),
         version when not is_nil(version) <- Plugins.get_plugin_version(version_id),
         true <- version.plugin_id == plugin.id,
         {:ok, _deleted} <- Plugins.delete_plugin_version(version) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "plugin_version.deleted", "plugin_version", version.id,
        project_id: project.id,
        changes: %{plugin_id: plugin.id, version: version.version}
      )

      send_resp(conn, :no_content, "")
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Version not found"})

      false ->
        conn |> put_status(:not_found) |> json(%{error: "Version not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})
    end
  end

  ## Service Plugin Chain

  def attach(conn, %{"project_slug" => project_slug, "id" => service_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         attrs <- %{
           service_id: service.id,
           plugin_id: params["plugin_id"],
           plugin_version_id: params["plugin_version_id"],
           position: params["position"] || 0,
           enabled: Map.get(params, "enabled", true),
           config_override: params["config_override"] || %{}
         },
         {:ok, sp} <- Plugins.attach_plugin(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service_plugin.attached", "service_plugin", sp.id,
        project_id: project.id,
        changes: %{service_id: service.id, plugin_id: params["plugin_id"]}
      )

      sp = Plugins.get_service_plugin(sp.id)

      conn
      |> put_status(:created)
      |> json(%{service_plugin: service_plugin_to_json(sp)})
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
        %{"project_slug" => project_slug, "id" => service_id, "pid" => plugin_id} = params
      ) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         sp when not is_nil(sp) <- Plugins.get_service_plugin_by(service.id, plugin_id),
         {:ok, updated} <- Plugins.update_service_plugin(sp, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service_plugin.updated", "service_plugin", updated.id,
        project_id: project.id
      )

      updated = Plugins.get_service_plugin(updated.id)

      conn
      |> put_status(:ok)
      |> json(%{service_plugin: service_plugin_to_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Service plugin not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :service_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Service not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def detach(conn, %{"project_slug" => project_slug, "id" => service_id, "pid" => plugin_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, service} <- get_service(service_id, project.id),
         sp when not is_nil(sp) <- Plugins.get_service_plugin_by(service.id, plugin_id),
         {:ok, _deleted} <- Plugins.detach_plugin(sp) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "service_plugin.detached", "service_plugin", sp.id,
        project_id: project.id
      )

      send_resp(conn, :no_content, "")
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Service plugin not found"})

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

      case Plugins.reorder_service_plugins(service.id, pairs) do
        {:ok, :ok} ->
          api_key = conn.assigns.current_api_key

          Audit.log_api_key_action(api_key, "service_plugin.reordered", "service", service.id,
            project_id: project.id
          )

          chain = Plugins.list_service_plugins(service.id)

          conn
          |> put_status(:ok)
          |> json(%{service_plugins: Enum.map(chain, &service_plugin_to_json/1)})

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

  ## Marketplace

  def marketplace(conn, params) do
    plugins = Plugins.list_marketplace_plugins(plugin_type: params["type"])

    conn
    |> put_status(:ok)
    |> json(%{
      plugins: Enum.map(plugins, &plugin_to_json/1),
      total: length(plugins)
    })
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_plugin(id, project_id) do
    case Plugins.get_plugin(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = plugin -> {:ok, plugin}
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

  defp decode_binary(nil), do: {:error, :invalid_base64}

  defp decode_binary(base64) when is_binary(base64) do
    case Base.decode64(base64) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_base64}
    end
  end

  defp plugin_to_json(plugin) do
    %{
      id: plugin.id,
      name: plugin.name,
      slug: plugin.slug,
      description: plugin.description,
      plugin_type: plugin.plugin_type,
      config_schema: plugin.config_schema,
      default_config: plugin.default_config,
      enabled: plugin.enabled,
      public: plugin.public,
      author: plugin.author,
      project_id: plugin.project_id,
      inserted_at: plugin.inserted_at,
      updated_at: plugin.updated_at
    }
  end

  defp version_to_json(version) do
    %{
      id: version.id,
      version: version.version,
      checksum: version.checksum,
      file_size: version.file_size,
      changelog: version.changelog,
      metadata: version.metadata,
      plugin_id: version.plugin_id,
      inserted_at: version.inserted_at,
      updated_at: version.updated_at
    }
  end

  defp service_plugin_to_json(sp) do
    %{
      id: sp.id,
      position: sp.position,
      enabled: sp.enabled,
      config_override: sp.config_override,
      service_id: sp.service_id,
      plugin_id: sp.plugin_id,
      plugin_version_id: sp.plugin_version_id,
      plugin: plugin_to_json(sp.plugin),
      inserted_at: sp.inserted_at,
      updated_at: sp.updated_at
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
