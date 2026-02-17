defmodule ZentinelCp.Services.AuthPolicy do
  @moduledoc """
  Auth policy schema for proxy-level authentication configuration.

  Auth policies define how the proxy validates incoming requests (JWT, API key,
  basic auth, forward auth, mTLS). Policies are reusable across services.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @auth_types ~w(jwt api_key basic forward_auth mtls)

  schema "auth_policies" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :auth_type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :services, ZentinelCp.Services.Service

    timestamps(type: :utc_datetime)
  end

  def create_changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :description, :auth_type, :config, :enabled, :project_id])
    |> validate_required([:name, :auth_type, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:auth_type, @auth_types)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :description, :auth_type, :config, :enabled])
    |> validate_required([:name, :auth_type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:auth_type, @auth_types)
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
