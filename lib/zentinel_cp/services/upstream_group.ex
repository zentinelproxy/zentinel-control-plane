defmodule ZentinelCp.Services.UpstreamGroup do
  @moduledoc """
  Upstream group schema for load balancing across multiple targets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ZentinelCp.Services.UpstreamTarget

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @algorithms ~w(round_robin least_conn ip_hash consistent_hash weighted random)

  schema "upstream_groups" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :algorithm, :string, default: "round_robin"
    field :sticky_sessions, :map, default: %{}
    field :health_check, :map, default: %{}
    field :circuit_breaker, :map, default: %{}

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :trust_store, ZentinelCp.Services.TrustStore
    has_many :targets, UpstreamTarget

    timestamps(type: :utc_datetime)
  end

  def create_changeset(group, attrs) do
    group
    |> cast(attrs, [
      :name,
      :description,
      :algorithm,
      :sticky_sessions,
      :health_check,
      :circuit_breaker,
      :project_id,
      :trust_store_id
    ])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:algorithm, @algorithms)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:trust_store_id)
  end

  def update_changeset(group, attrs) do
    group
    |> cast(attrs, [
      :name,
      :description,
      :algorithm,
      :sticky_sessions,
      :health_check,
      :circuit_breaker,
      :trust_store_id
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:algorithm, @algorithms)
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
