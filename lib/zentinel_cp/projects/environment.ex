defmodule ZentinelCp.Projects.Environment do
  @moduledoc """
  Environment schema representing deployment stages like dev, staging, prod.

  Environments have an ordinal that defines the promotion order.
  Lower ordinals are earlier in the pipeline (dev=0, staging=1, prod=2).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_colors %{
    "dev" => "#22c55e",
    "staging" => "#eab308",
    "prod" => "#ef4444"
  }

  schema "environments" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :color, :string, default: "#6366f1"
    field :ordinal, :integer, default: 0
    field :settings, :map, default: %{}

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :nodes, ZentinelCp.Nodes.Node
    has_many :rollouts, ZentinelCp.Rollouts.Rollout
    has_many :bundle_promotions, ZentinelCp.Bundles.BundlePromotion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an environment.
  """
  def create_changeset(environment, attrs) do
    environment
    |> cast(attrs, [:name, :description, :color, :ordinal, :settings, :project_id])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 50)
    |> generate_slug()
    |> validate_slug()
    |> maybe_set_color()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating an environment.
  """
  def update_changeset(environment, attrs) do
    environment
    |> cast(attrs, [:name, :description, :color, :ordinal, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
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
          |> String.slice(0, 30)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 30)
  end

  defp maybe_set_color(changeset) do
    if get_change(changeset, :color) do
      changeset
    else
      slug = get_change(changeset, :slug) || get_field(changeset, :slug)
      default_color = Map.get(@default_colors, slug, "#6366f1")
      put_change(changeset, :color, default_color)
    end
  end

  @doc """
  Returns whether approval is required for rollouts in this environment.
  """
  def approval_required?(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "approval_required", false)
  end

  @doc """
  Returns the number of approvals needed for rollouts in this environment.
  """
  def approvals_needed(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "approvals_needed", 1)
  end

  @doc """
  Returns whether this environment allows auto-rollback.
  """
  def auto_rollback_enabled?(%__MODULE__{settings: settings}) do
    Map.get(settings || %{}, "auto_rollback_enabled", true)
  end

  @doc """
  Creates default environments for a project.
  Returns a list of environment attributes.
  """
  def default_environments(project_id) do
    [
      %{
        name: "Development",
        slug: "dev",
        description: "Development environment",
        color: "#22c55e",
        ordinal: 0,
        project_id: project_id,
        settings: %{"approval_required" => false}
      },
      %{
        name: "Staging",
        slug: "staging",
        description: "Staging/QA environment",
        color: "#eab308",
        ordinal: 1,
        project_id: project_id,
        settings: %{"approval_required" => false}
      },
      %{
        name: "Production",
        slug: "prod",
        description: "Production environment",
        color: "#ef4444",
        ordinal: 2,
        project_id: project_id,
        settings: %{"approval_required" => true, "approvals_needed" => 1}
      }
    ]
  end
end
