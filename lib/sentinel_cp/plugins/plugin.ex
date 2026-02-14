defmodule SentinelCp.Plugins.Plugin do
  @moduledoc """
  Plugin schema for user-uploadable proxy plugins (Wasm/Lua).

  Plugins are project-scoped binaries that run in the Sentinel proxy's
  plugin runtime. A nil `project_id` indicates a marketplace/global plugin.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @plugin_types ~w(wasm lua)

  schema "plugins" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :plugin_type, :string
    field :config_schema, :map, default: %{}
    field :default_config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :public, :boolean, default: false
    field :author, :string

    belongs_to :project, SentinelCp.Projects.Project
    has_many :plugin_versions, SentinelCp.Plugins.PluginVersion
    has_many :service_plugins, SentinelCp.Plugins.ServicePlugin

    timestamps(type: :utc_datetime)
  end

  def plugin_types, do: @plugin_types

  def create_changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [
      :name,
      :description,
      :plugin_type,
      :config_schema,
      :default_config,
      :enabled,
      :public,
      :author,
      :project_id
    ])
    |> validate_required([:name, :plugin_type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:plugin_type, @plugin_types)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [
      :name,
      :description,
      :config_schema,
      :default_config,
      :enabled,
      :public,
      :author
    ])
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
