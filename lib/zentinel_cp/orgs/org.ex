defmodule ZentinelCp.Orgs.Org do
  @moduledoc """
  Organization schema — the top-level tenant boundary.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "orgs" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}

    has_many :org_memberships, ZentinelCp.Orgs.OrgMembership
    has_many :projects, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an org.
  """
  def create_changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating an org.
  """
  def update_changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 50)
  end
end
