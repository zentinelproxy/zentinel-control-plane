defmodule ZentinelCp.Services.Middleware do
  @moduledoc """
  Middleware schema for reusable proxy middleware definitions.

  Middleware entities are project-scoped building blocks (rate limiting, CORS,
  compression, etc.) that can be attached to services in an ordered chain via
  ServiceMiddleware join records.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @middleware_types ~w(rate_limit cache cors compression headers access_control security path_rewrite request_transform response_transform auth custom)

  schema "middlewares" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :middleware_type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :service_middlewares, ZentinelCp.Services.ServiceMiddleware

    timestamps(type: :utc_datetime)
  end

  def middleware_types, do: @middleware_types

  def create_changeset(middleware, attrs) do
    middleware
    |> cast(attrs, [:name, :description, :middleware_type, :config, :enabled, :project_id])
    |> validate_required([:name, :middleware_type, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:middleware_type, @middleware_types)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(middleware, attrs) do
    middleware
    |> cast(attrs, [:name, :description, :config, :enabled])
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
