defmodule ZentinelCpWeb.Api.VaultController do
  @moduledoc """
  API controller for HashiCorp Vault integration.
  Manages per-project Vault configuration.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Secrets, Projects, Audit}

  def show(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      case Secrets.get_vault_config(project.id) do
        nil ->
          conn |> put_status(:ok) |> json(%{vault: nil})

        config ->
          conn |> put_status(:ok) |> json(%{vault: vault_to_json(config)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- build_vault_attrs(params, project.id),
         {:ok, config} <- Secrets.create_vault_config(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "vault.configured", "vault_config", config.id,
        project_id: project.id,
        changes: %{vault_addr: config.vault_addr, auth_method: config.auth_method}
      )

      conn
      |> put_status(:created)
      |> json(%{vault: vault_to_json(config)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, config} <- get_vault_config(project.id),
         attrs <- build_vault_attrs(params, project.id),
         {:ok, updated} <- Secrets.update_vault_config(config, attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "vault.updated", "vault_config", updated.id,
        project_id: project.id,
        changes: %{vault_addr: updated.vault_addr, auth_method: updated.auth_method}
      )

      conn
      |> put_status(:ok)
      |> json(%{vault: vault_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_configured} ->
        conn |> put_status(:not_found) |> json(%{error: "Vault not configured for this project"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, config} <- get_vault_config(project.id),
         {:ok, _} <- Secrets.delete_vault_config(config) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "vault.removed", "vault_config", config.id,
        project_id: project.id
      )

      conn
      |> put_status(:ok)
      |> json(%{deleted: true})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_configured} ->
        conn |> put_status(:not_found) |> json(%{error: "Vault not configured for this project"})
    end
  end

  def test_connection(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      case Secrets.test_vault_connection(project.id) do
        {:ok, health} ->
          conn
          |> put_status(:ok)
          |> json(%{
            status: "ok",
            initialized: health.initialized,
            sealed: health.sealed,
            version: health.version
          })

        {:error, :not_configured} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Vault not configured for this project"})

        {:error, reason} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "Vault connection failed: #{inspect(reason)}"})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  # Private helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_vault_config(project_id) do
    case Secrets.get_vault_config(project_id) do
      nil -> {:error, :not_configured}
      config -> {:ok, config}
    end
  end

  defp build_vault_attrs(params, project_id) do
    %{
      project_id: project_id,
      enabled: params["enabled"] || false,
      vault_addr: params["vault_addr"],
      auth_method: params["auth_method"] || "token",
      auth_config_plaintext: params["auth_config"],
      mount_path: params["mount_path"] || "secret",
      base_path: params["base_path"],
      namespace: params["namespace"]
    }
  end

  defp vault_to_json(config) do
    %{
      id: config.id,
      project_id: config.project_id,
      enabled: config.enabled,
      vault_addr: config.vault_addr,
      auth_method: config.auth_method,
      mount_path: config.mount_path,
      base_path: config.base_path,
      namespace: config.namespace,
      connection_status: config.connection_status,
      last_connected_at: config.last_connected_at,
      inserted_at: config.inserted_at,
      updated_at: config.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end
end
