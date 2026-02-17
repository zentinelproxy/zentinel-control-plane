defmodule ZentinelCpWeb.Plugs.RequireScope do
  @moduledoc """
  Plug that enforces API key scope requirements.

  Checks that the authenticated API key has the required scope.
  Legacy keys with empty scopes retain full access.

  If the API key has a `project_id`, validates it matches the
  request's `:project_slug` parameter.

  ## Options

    * `:scope` - required scope string (e.g., `"bundles:write"`)

  ## Examples

      plug RequireScope, scope: "bundles:write"
      plug RequireScope, scope: "nodes:read"
  """
  import Plug.Conn

  alias ZentinelCp.Projects

  def init(opts) do
    scope = Keyword.fetch!(opts, :scope)
    %{scope: scope}
  end

  def call(conn, %{scope: required_scope}) do
    api_key = conn.assigns[:current_api_key]

    with :ok <- check_scope(api_key, required_scope),
         {:ok, conn} <- check_project(conn, api_key) do
      conn
    else
      {:error, :forbidden} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          403,
          Jason.encode!(%{error: "Insufficient scope. Required: #{required_scope}"})
        )
        |> halt()

      {:error, :project_not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Project not found"}))
        |> halt()

      {:error, :project_mismatch} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Project not found"}))
        |> halt()
    end
  end

  defp check_scope(api_key, required_scope) do
    if api_key.scopes == [] or required_scope in api_key.scopes do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp check_project(conn, api_key) do
    project_slug = conn.params["project_slug"]

    cond do
      is_nil(api_key.project_id) and is_nil(project_slug) ->
        {:ok, conn}

      is_nil(api_key.project_id) ->
        resolve_and_assign_project(conn, project_slug)

      not is_nil(project_slug) ->
        validate_project_match(conn, api_key.project_id, project_slug)

      true ->
        {:ok, conn}
    end
  end

  defp resolve_and_assign_project(conn, project_slug) do
    case Projects.get_project_by_slug(project_slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, assign(conn, :current_project, project)}
    end
  end

  defp validate_project_match(conn, key_project_id, project_slug) do
    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:error, :project_not_found}

      %{id: ^key_project_id} = project ->
        {:ok, assign(conn, :current_project, project)}

      _other ->
        {:error, :project_mismatch}
    end
  end
end
