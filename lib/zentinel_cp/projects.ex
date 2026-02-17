defmodule ZentinelCp.Projects do
  @moduledoc """
  The Projects context handles project (tenant) management.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Projects.{Environment, Project}

  @doc """
  Returns the list of projects, optionally scoped to an org.
  """
  def list_projects(opts \\ []) do
    query = from(p in Project, order_by: [asc: p.name])

    query =
      case Keyword.get(opts, :org_id) do
        nil -> query
        org_id -> where(query, [p], p.org_id == ^org_id)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single project by ID.
  """
  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a single project by ID, raises if not found.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Gets a single project by slug.
  """
  def get_project_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Project, slug: slug)
  end

  @doc """
  Gets a single project by GitHub repository name (e.g. "owner/repo").
  """
  def get_project_by_github_repo(repo) when is_binary(repo) do
    Repo.get_by(Project, github_repo: repo)
  end

  @doc """
  Creates a project.
  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.create_changeset(project, attrs)
  end

  @doc """
  Lists all projects that have drift alert thresholds configured.
  """
  def list_projects_with_drift_alerts do
    from(p in Project)
    |> Repo.all()
    |> Enum.filter(fn project ->
      Project.drift_alert_threshold(project) != nil ||
        Project.drift_alert_node_count(project) != nil
    end)
  end

  ## Environments

  @doc """
  Lists all environments for a project, ordered by ordinal.
  """
  def list_environments(project_id) do
    from(e in Environment,
      where: e.project_id == ^project_id,
      order_by: [asc: e.ordinal, asc: e.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets an environment by ID.
  """
  def get_environment(id), do: Repo.get(Environment, id)

  @doc """
  Gets an environment by ID, raises if not found.
  """
  def get_environment!(id), do: Repo.get!(Environment, id)

  @doc """
  Gets an environment by project and slug.
  """
  def get_environment_by_slug(project_id, slug) do
    Repo.get_by(Environment, project_id: project_id, slug: slug)
  end

  @doc """
  Creates an environment.
  """
  def create_environment(attrs) do
    %Environment{}
    |> Environment.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an environment.
  """
  def update_environment(%Environment{} = environment, attrs) do
    environment
    |> Environment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an environment.
  """
  def delete_environment(%Environment{} = environment) do
    Repo.delete(environment)
  end

  @doc """
  Creates default environments (dev, staging, prod) for a project.
  """
  def create_default_environments(project_id) do
    environments = Environment.default_environments(project_id)

    Repo.transaction(fn ->
      Enum.map(environments, fn attrs ->
        case create_environment(attrs) do
          {:ok, env} -> env
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Gets the next environment in the promotion pipeline.
  Returns nil if this is the last environment.
  """
  def get_next_environment(%Environment{} = environment) do
    from(e in Environment,
      where: e.project_id == ^environment.project_id,
      where: e.ordinal > ^environment.ordinal,
      order_by: [asc: e.ordinal],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the previous environment in the promotion pipeline.
  Returns nil if this is the first environment.
  """
  def get_previous_environment(%Environment{} = environment) do
    from(e in Environment,
      where: e.project_id == ^environment.project_id,
      where: e.ordinal < ^environment.ordinal,
      order_by: [desc: e.ordinal],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns environment stats (node counts) for a project.
  """
  def get_environment_stats(project_id) do
    from(e in Environment,
      where: e.project_id == ^project_id,
      left_join: n in assoc(e, :nodes),
      group_by: e.id,
      select: {e.id, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
