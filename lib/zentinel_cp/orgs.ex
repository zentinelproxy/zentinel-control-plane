defmodule ZentinelCp.Orgs do
  @moduledoc """
  The Orgs context handles organization management and membership.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Orgs.{Org, OrgMembership}

  ## Org CRUD

  @doc """
  Returns the list of orgs.
  """
  def list_orgs do
    Repo.all(from o in Org, order_by: [asc: o.name])
  end

  @doc """
  Lists orgs that a user is a member of.
  """
  def list_user_orgs(user_id) do
    from(o in Org,
      join: m in OrgMembership,
      on: m.org_id == o.id,
      where: m.user_id == ^user_id,
      order_by: [asc: o.name],
      select: {o, m.role}
    )
    |> Repo.all()
  end

  @doc """
  Gets a single org by ID.
  """
  def get_org(id), do: Repo.get(Org, id)

  @doc """
  Gets a single org by ID, raises if not found.
  """
  def get_org!(id), do: Repo.get!(Org, id)

  @doc """
  Gets a single org by slug.
  """
  def get_org_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Org, slug: slug)
  end

  @doc """
  Creates an org.
  """
  def create_org(attrs \\ %{}) do
    %Org{}
    |> Org.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an org and adds the given user as admin.
  """
  def create_org_with_owner(attrs, user) do
    Repo.transaction(fn ->
      with {:ok, org} <- create_org(attrs),
           {:ok, _membership} <- add_member(org, user, "admin") do
        org
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an org.
  """
  def update_org(%Org{} = org, attrs) do
    org
    |> Org.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an org.
  """
  def delete_org(%Org{} = org) do
    Repo.delete(org)
  end

  ## Membership Management

  @doc """
  Adds a user to an org with the given role.
  """
  def add_member(%Org{} = org, user, role \\ "reader") do
    %OrgMembership{}
    |> OrgMembership.create_changeset(%{
      org_id: org.id,
      user_id: user.id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Updates a member's role within an org.
  """
  def update_member_role(%OrgMembership{} = membership, role) do
    membership
    |> OrgMembership.update_role_changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a user from an org.
  """
  def remove_member(%Org{} = org, user) do
    from(m in OrgMembership,
      where: m.org_id == ^org.id and m.user_id == ^user.id
    )
    |> Repo.delete_all()
  end

  @doc """
  Lists all members of an org.
  """
  def list_members(%Org{} = org) do
    from(m in OrgMembership,
      where: m.org_id == ^org.id,
      join: u in assoc(m, :user),
      preload: [user: u],
      order_by: [asc: u.email]
    )
    |> Repo.all()
  end

  @doc """
  Gets a user's membership in an org.
  """
  def get_membership(org_id, user_id) do
    Repo.get_by(OrgMembership, org_id: org_id, user_id: user_id)
  end

  @doc """
  Gets a user's role within an org.
  Returns nil if the user is not a member.
  """
  def get_user_role(org_id, user_id) do
    from(m in OrgMembership,
      where: m.org_id == ^org_id and m.user_id == ^user_id,
      select: m.role
    )
    |> Repo.one()
  end

  @doc """
  Checks if a user has the given role (or higher) in an org.
  Role hierarchy: admin > operator > reader.
  """
  def user_has_role?(org_id, user_id, required_role) do
    case get_user_role(org_id, user_id) do
      nil -> false
      role -> role_at_least?(role, required_role)
    end
  end

  defp role_at_least?(actual, required) do
    role_level(actual) >= role_level(required)
  end

  defp role_level("admin"), do: 3
  defp role_level("operator"), do: 2
  defp role_level("reader"), do: 1
  defp role_level(_), do: 0

  @doc """
  Returns the default org, creating it if it doesn't exist.
  Used for data migration and single-org setups.
  """
  def get_or_create_default_org do
    case get_org_by_slug("default") do
      nil -> create_org(%{name: "Default"})
      org -> {:ok, org}
    end
  end
end
