defmodule SentinelCpWeb.Api.TemplateController do
  @moduledoc """
  API controller for service template management.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Services, Projects}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      templates = Services.list_templates(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        templates: Enum.map(templates, &template_to_json/1),
        total: length(templates)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Services.get_template(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Template not found"})

      template ->
        conn |> put_status(:ok) |> json(%{template: template_to_json(template)})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, template} <- Services.create_template(attrs) do
      conn
      |> put_status(:created)
      |> json(%{template: template_to_json(template)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Services.get_template(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Template not found"})

      template ->
        case Services.update_template(template, params) do
          {:ok, updated} ->
            conn |> put_status(:ok) |> json(%{template: template_to_json(updated)})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Services.get_template(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Template not found"})

      template ->
        case Services.delete_template(template) do
          {:ok, _} -> send_resp(conn, :no_content, "")
          {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "Could not delete template"})
        end
    end
  end

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp template_to_json(template) do
    %{
      id: template.id,
      name: template.name,
      slug: template.slug,
      description: template.description,
      category: template.category,
      template_data: template.template_data,
      version: template.version,
      is_builtin: template.is_builtin,
      project_id: template.project_id,
      inserted_at: template.inserted_at,
      updated_at: template.updated_at
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
