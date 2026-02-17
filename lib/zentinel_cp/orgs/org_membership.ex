defmodule ZentinelCp.Orgs.OrgMembership do
  @moduledoc """
  OrgMembership schema — joins users to organizations with a role.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(admin operator reader)

  schema "org_memberships" do
    belongs_to :org, ZentinelCp.Orgs.Org
    belongs_to :user, ZentinelCp.Accounts.User

    field :role, :string, default: "reader"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an org membership.
  """
  def create_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:org_id, :user_id, :role])
    |> validate_required([:org_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:org_id, :user_id])
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating the role.
  """
  def update_role_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
  end
end
