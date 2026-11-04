defmodule ZentinelCp.Access do
  @moduledoc """
  Tenant access rules for API keys.

  An API key can do no more than the user who owns it. A global admin can reach
  every org. Any other user needs membership of the project's org, and at least
  the `operator` role for anything beyond a `:read` scope. Removing a member
  therefore immediately limits their keys.
  """

  import Ecto.Query, warn: false

  alias ZentinelCp.Accounts.User
  alias ZentinelCp.Orgs
  alias ZentinelCp.Orgs.OrgMembership
  alias ZentinelCp.Projects
  alias ZentinelCp.Projects.Project
  alias ZentinelCp.Repo

  @doc """
  Returns true if the key may use `required_scope` on the project.
  Accepts a project or a project ID.
  """
  def api_key_allowed?(api_key, project, required_scope \\ nil)

  def api_key_allowed?(nil, _project, _required_scope), do: false
  def api_key_allowed?(_api_key, nil, _required_scope), do: false

  def api_key_allowed?(api_key, project_id, required_scope) when is_binary(project_id) do
    case Ecto.UUID.cast(project_id) do
      {:ok, id} -> api_key_allowed?(api_key, Projects.get_project(id), required_scope)
      :error -> false
    end
  end

  def api_key_allowed?(api_key, %Project{} = project, required_scope) do
    key_project_matches?(api_key, project) and scope_held?(api_key, required_scope) and
      owner_allowed?(api_key.user_id, project.org_id, required_scope)
  end

  @doc "Returns true if the key holds the scope. Keys with no scopes hold all of them."
  def scope_held?(_api_key, nil), do: true
  def scope_held?(%{scopes: []}, _required_scope), do: true
  def scope_held?(%{scopes: scopes}, required_scope), do: required_scope in scopes

  @doc "Lists the projects a key can see, optionally within one org."
  def visible_projects(api_key, opts \\ []) do
    query = from(p in Project, order_by: [asc: p.name])

    query =
      case opts[:org_id] do
        nil -> query
        org_id -> where(query, [p], p.org_id == ^org_id)
      end

    query =
      case api_key.project_id do
        nil -> query
        project_id -> where(query, [p], p.id == ^project_id)
      end

    if global_admin?(api_key.user_id) do
      Repo.all(query)
    else
      query
      |> join(:inner, [p], m in OrgMembership,
        on: m.org_id == p.org_id and m.user_id == ^api_key.user_id
      )
      |> Repo.all()
    end
  end

  @doc "Returns true if the user is a global admin."
  def global_admin?(nil), do: false

  def global_admin?(user_id) do
    Repo.exists?(from(u in User, where: u.id == ^user_id and u.role == "admin"))
  end

  @doc "Returns true if the user may create keys for the project."
  def user_can_manage_project?(user_id, %Project{} = project) do
    owner_allowed?(user_id, project.org_id, "api_keys:admin")
  end

  defp key_project_matches?(%{project_id: nil}, _project), do: true
  defp key_project_matches?(%{project_id: id}, %Project{id: id}), do: true
  defp key_project_matches?(_api_key, _project), do: false

  defp owner_allowed?(nil, _org_id, _required_scope), do: false

  defp owner_allowed?(user_id, org_id, required_scope) do
    global_admin?(user_id) or
      Orgs.user_has_role?(org_id, user_id, required_role(required_scope))
  end

  defp required_role(nil), do: "reader"

  defp required_role(scope) do
    if String.ends_with?(scope, ":read"), do: "reader", else: "operator"
  end
end
