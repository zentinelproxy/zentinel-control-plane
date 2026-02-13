defmodule SentinelCpWeb.Api.UpstreamGroupController do
  @moduledoc """
  API controller for upstream group management.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Services, Projects, Audit}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      groups = Services.list_upstream_groups(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        upstream_groups: Enum.map(groups, &group_to_json/1),
        total: length(groups)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, group} <- get_group(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{upstream_group: group_to_json(group)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, group} <- Services.create_upstream_group(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "upstream_group.created", "upstream_group", group.id,
        project_id: project.id,
        changes: %{name: group.name}
      )

      group = Services.get_upstream_group(group.id)

      conn
      |> put_status(:created)
      |> json(%{upstream_group: group_to_json(group)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, group} <- get_group(id, project.id),
         {:ok, updated} <- Services.update_upstream_group(group, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "upstream_group.updated", "upstream_group", group.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      updated = Services.get_upstream_group(updated.id)

      conn
      |> put_status(:ok)
      |> json(%{upstream_group: group_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, group} <- get_group(id, project.id),
         {:ok, _deleted} <- Services.delete_upstream_group(group) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "upstream_group.deleted", "upstream_group", group.id,
        project_id: project.id,
        changes: %{name: group.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})
    end
  end

  def add_target(conn, %{"project_slug" => project_slug, "id" => group_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, group} <- get_group(group_id, project.id),
         attrs <- Map.put(params, "upstream_group_id", group.id),
         {:ok, target} <- Services.add_upstream_target(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "upstream_target.added", "upstream_group", group.id,
        project_id: project.id,
        changes: %{host: target.host, port: target.port}
      )

      conn
      |> put_status(:created)
      |> json(%{target: target_to_json(target)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update_target(conn, %{"project_slug" => project_slug, "id" => group_id, "target_id" => target_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         target when not is_nil(target) <- Services.get_upstream_target(target_id),
         {:ok, updated} <- Services.update_upstream_target(target, params) do
      conn
      |> put_status(:ok)
      |> json(%{target: target_to_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Target not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete_target(conn, %{"project_slug" => project_slug, "id" => group_id, "target_id" => target_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         target when not is_nil(target) <- Services.get_upstream_target(target_id),
         {:ok, _} <- Services.remove_upstream_target(target) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Target not found"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})
    end
  end

  # Discovery endpoints

  def show_discovery(conn, %{"project_slug" => project_slug, "id" => group_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         source when not is_nil(source) <- Services.get_discovery_source_for_group(group_id) do
      conn
      |> put_status(:ok)
      |> json(%{discovery_source: discovery_source_to_json(source)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No discovery source for this group"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})
    end
  end

  def create_discovery(conn, %{"project_slug" => project_slug, "id" => group_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         attrs <- Map.merge(params, %{"upstream_group_id" => group_id, "project_id" => project.id}),
         {:ok, source} <- Services.create_discovery_source(attrs) do
      conn
      |> put_status(:created)
      |> json(%{discovery_source: discovery_source_to_json(source)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update_discovery(conn, %{"project_slug" => project_slug, "id" => group_id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         source when not is_nil(source) <- Services.get_discovery_source_for_group(group_id),
         {:ok, updated} <- Services.update_discovery_source(source, params) do
      conn
      |> put_status(:ok)
      |> json(%{discovery_source: discovery_source_to_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No discovery source for this group"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete_discovery(conn, %{"project_slug" => project_slug, "id" => group_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         source when not is_nil(source) <- Services.get_discovery_source_for_group(group_id),
         {:ok, _} <- Services.delete_discovery_source(source) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No discovery source for this group"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})
    end
  end

  def sync_discovery(conn, %{"project_slug" => project_slug, "id" => group_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, _group} <- get_group(group_id, project.id),
         source when not is_nil(source) <- Services.get_discovery_source_for_group(group_id),
         {:ok, result} <- Services.sync_discovery_source(source) do
      conn
      |> put_status(:ok)
      |> json(%{
        sync_result: %{
          added: result.added,
          removed: result.removed,
          kept: result.kept
        }
      })
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No discovery source for this group"})

      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Upstream group not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_group(id, project_id) do
    case Services.get_upstream_group(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = group -> {:ok, group}
      _ -> {:error, :not_found}
    end
  end

  defp group_to_json(group) do
    %{
      id: group.id,
      name: group.name,
      slug: group.slug,
      description: group.description,
      algorithm: group.algorithm,
      sticky_sessions: group.sticky_sessions,
      health_check: group.health_check,
      circuit_breaker: group.circuit_breaker,
      project_id: group.project_id,
      targets: Enum.map(group.targets || [], &target_to_json/1),
      inserted_at: group.inserted_at,
      updated_at: group.updated_at
    }
  end

  defp target_to_json(target) do
    %{
      id: target.id,
      host: target.host,
      port: target.port,
      weight: target.weight,
      max_connections: target.max_connections,
      enabled: target.enabled,
      inserted_at: target.inserted_at,
      updated_at: target.updated_at
    }
  end

  defp discovery_source_to_json(source) do
    %{
      id: source.id,
      source_type: source.source_type,
      hostname: source.hostname,
      config: mask_config(source.config),
      sync_interval_seconds: source.sync_interval_seconds,
      auto_sync: source.auto_sync,
      last_synced_at: source.last_synced_at,
      last_sync_status: source.last_sync_status,
      last_sync_error: source.last_sync_error,
      last_sync_targets_count: source.last_sync_targets_count,
      upstream_group_id: source.upstream_group_id,
      project_id: source.project_id,
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    }
  end

  defp mask_config(nil), do: %{}
  defp mask_config(config) when is_map(config) do
    if Map.has_key?(config, "token") do
      Map.put(config, "token", "****")
    else
      config
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
