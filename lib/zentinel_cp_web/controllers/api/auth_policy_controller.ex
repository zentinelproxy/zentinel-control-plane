defmodule ZentinelCpWeb.Api.AuthPolicyController do
  @moduledoc """
  API controller for proxy-level auth policy management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      policies = Services.list_auth_policies(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        auth_policies: Enum.map(policies, &auth_policy_to_json/1),
        total: length(policies)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, policy} <- get_policy(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{auth_policy: auth_policy_to_json(policy)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Auth policy not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, policy} <- Services.create_auth_policy(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "auth_policy.created", "auth_policy", policy.id,
        project_id: project.id,
        changes: %{name: policy.name, auth_type: policy.auth_type}
      )

      conn
      |> put_status(:created)
      |> json(%{auth_policy: auth_policy_to_json(policy)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, policy} <- get_policy(id, project.id),
         {:ok, updated} <- Services.update_auth_policy(policy, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "auth_policy.updated", "auth_policy", policy.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{auth_policy: auth_policy_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Auth policy not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, policy} <- get_policy(id, project.id),
         {:ok, _deleted} <- Services.delete_auth_policy(policy) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "auth_policy.deleted", "auth_policy", policy.id,
        project_id: project.id,
        changes: %{name: policy.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Auth policy not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_policy(id, project_id) do
    case Services.get_auth_policy(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = policy -> {:ok, policy}
      _ -> {:error, :not_found}
    end
  end

  defp auth_policy_to_json(policy) do
    %{
      id: policy.id,
      name: policy.name,
      slug: policy.slug,
      description: policy.description,
      auth_type: policy.auth_type,
      config: policy.config,
      enabled: policy.enabled,
      project_id: policy.project_id,
      inserted_at: policy.inserted_at,
      updated_at: policy.updated_at
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
