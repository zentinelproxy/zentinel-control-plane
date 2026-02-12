defmodule SentinelCp.Services.ServiceTemplate do
  @moduledoc """
  Schema for service configuration templates.

  Templates provide preset configurations for common service patterns,
  making it easy to create new services with best-practice defaults.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(api web websocket static auth utility)

  schema "service_templates" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :category, :string
    field :template_data, :map, default: %{}
    field :version, :integer, default: 1
    field :is_builtin, :boolean, default: false

    belongs_to :project, SentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :category, :template_data, :version, :is_builtin, :project_id])
    |> validate_required([:name, :category])
    |> validate_inclusion(:category, @categories)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> unique_constraint([:slug], name: :service_templates_builtin_slug_index, error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :category, :template_data, :version])
    |> validate_required([:name, :category])
    |> validate_inclusion(:category, @categories)
  end

  def categories, do: @categories

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
