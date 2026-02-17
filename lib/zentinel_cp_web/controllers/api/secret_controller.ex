defmodule ZentinelCpWeb.Api.SecretController do
  @moduledoc """
  API controller for secrets management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Secrets, Projects, Audit}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      secrets = Secrets.list_secrets(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        secrets: Enum.map(secrets, &secret_to_json/1),
        total: length(secrets)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, secret} <- get_secret(id, project.id) do
      Audit.log_api_key_action(
        conn.assigns.current_api_key,
        "secret.accessed",
        "secret",
        secret.id,
        project_id: project.id
      )

      conn
      |> put_status(:ok)
      |> json(%{secret: secret_to_json(secret)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Secret not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- %{
           name: params["name"],
           value: params["value"],
           description: params["description"],
           environment: params["environment"],
           project_id: project.id
         },
         {:ok, secret} <- Secrets.create_secret(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "secret.created", "secret", secret.id,
        project_id: project.id,
        changes: %{name: secret.name, environment: secret.environment}
      )

      conn
      |> put_status(:created)
      |> json(%{secret: secret_to_json(secret)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, secret} <- get_secret(id, project.id),
         attrs <- build_update_attrs(params),
         {:ok, updated} <- Secrets.update_secret(secret, attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "secret.updated", "secret", updated.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{secret: secret_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Secret not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, secret} <- get_secret(id, project.id),
         {:ok, _} <- Secrets.delete_secret(secret) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "secret.deleted", "secret", secret.id,
        project_id: project.id,
        changes: %{name: secret.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{deleted: true})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Secret not found"})
    end
  end

  def rotate(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, secret} <- get_secret(id, project.id),
         {:ok, rotated} <- Secrets.rotate_secret(secret, params["value"]) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "secret.rotated", "secret", rotated.id,
        project_id: project.id,
        changes: %{name: rotated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{secret: secret_to_json(rotated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Secret not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_secret(id, project_id) do
    case Secrets.get_secret(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = secret -> {:ok, secret}
      _ -> {:error, :not_found}
    end
  end

  defp build_update_attrs(params) do
    attrs = %{}
    attrs = if params["value"], do: Map.put(attrs, :value, params["value"]), else: attrs

    attrs =
      if params["description"],
        do: Map.put(attrs, :description, params["description"]),
        else: attrs

    attrs
  end

  defp secret_to_json(secret) do
    %{
      id: secret.id,
      name: secret.name,
      slug: secret.slug,
      description: secret.description,
      environment: secret.environment,
      last_rotated_at: secret.last_rotated_at,
      inserted_at: secret.inserted_at,
      updated_at: secret.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end
end
