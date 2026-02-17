defmodule ZentinelCpWeb.Api.TrustStoreController do
  @moduledoc """
  API controller for trust store management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      trust_stores = Services.list_trust_stores(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        trust_stores: Enum.map(trust_stores, &trust_store_to_json/1),
        total: length(trust_stores)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ts} <- get_trust_store(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{trust_store: trust_store_to_json(ts)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Trust store not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, ts} <- Services.create_trust_store(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "trust_store.created", "trust_store", ts.id,
        project_id: project.id,
        changes: %{name: ts.name, cert_count: ts.cert_count}
      )

      conn
      |> put_status(:created)
      |> json(%{trust_store: trust_store_to_json(ts)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ts} <- get_trust_store(id, project.id),
         {:ok, updated} <- Services.update_trust_store(ts, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "trust_store.updated", "trust_store", ts.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{trust_store: trust_store_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Trust store not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ts} <- get_trust_store(id, project.id),
         {:ok, _deleted} <- Services.delete_trust_store(ts) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "trust_store.deleted", "trust_store", ts.id,
        project_id: project.id,
        changes: %{name: ts.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Trust store not found"})
    end
  end

  def download(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ts} <- get_trust_store(id, project.id) do
      conn
      |> put_resp_content_type("application/x-pem-file")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{ts.slug}.pem\"")
      |> send_resp(:ok, ts.certificates_pem)
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Trust store not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_trust_store(id, project_id) do
    case Services.get_trust_store(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = ts -> {:ok, ts}
      _ -> {:error, :not_found}
    end
  end

  defp trust_store_to_json(ts) do
    %{
      id: ts.id,
      name: ts.name,
      slug: ts.slug,
      description: ts.description,
      cert_count: ts.cert_count,
      subjects: ts.subjects,
      earliest_expiry: ts.earliest_expiry,
      latest_expiry: ts.latest_expiry,
      project_id: ts.project_id,
      inserted_at: ts.inserted_at,
      updated_at: ts.updated_at
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
