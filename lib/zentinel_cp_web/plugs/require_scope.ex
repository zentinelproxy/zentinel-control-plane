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

  alias ZentinelCp.{Access, Projects}

  def init(opts) do
    scope = Keyword.fetch!(opts, :scope)
    %{scope: scope}
  end

  def call(conn, %{scope: required_scope}) do
    api_key = conn.assigns[:current_api_key]

    with :ok <- check_scope(api_key, required_scope),
         {:ok, conn} <- check_project(conn, api_key, required_scope) do
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
    if Access.scope_held?(api_key, required_scope), do: :ok, else: {:error, :forbidden}
  end

  defp check_project(conn, api_key, required_scope) do
    case conn.params["project_slug"] do
      nil -> {:ok, conn}
      project_slug -> authorize_project(conn, api_key, project_slug, required_scope)
    end
  end

  # A project the key cannot reach looks the same as one that does not exist.
  defp authorize_project(conn, api_key, project_slug, required_scope) do
    project = Projects.get_project_by_slug(project_slug)

    cond do
      is_nil(project) ->
        {:error, :project_not_found}

      Access.api_key_allowed?(api_key, project, required_scope) ->
        {:ok, assign(conn, :current_project, project)}

      true ->
        {:error, :project_mismatch}
    end
  end
end
