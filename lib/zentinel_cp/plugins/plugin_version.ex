defmodule ZentinelCp.Plugins.PluginVersion do
  @moduledoc """
  Schema for versioned plugin binaries stored in S3.

  Each version has a semver string, S3 storage key, SHA256 checksum,
  and file size. The binary content lives in object storage.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plugin_versions" do
    field :version, :string
    field :storage_key, :string
    field :checksum, :string
    field :file_size, :integer
    field :changelog, :string
    field :metadata, :map, default: %{}

    belongs_to :plugin, ZentinelCp.Plugins.Plugin

    timestamps(type: :utc_datetime)
  end

  def changeset(plugin_version, attrs) do
    plugin_version
    |> cast(attrs, [
      :version,
      :storage_key,
      :checksum,
      :file_size,
      :changelog,
      :metadata,
      :plugin_id
    ])
    |> validate_required([:version, :storage_key, :checksum, :file_size, :plugin_id])
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+(-[\w.]+)?$/,
      message: "must be valid semver (e.g. 1.0.0 or 1.0.0-beta.1)"
    )
    |> validate_number(:file_size, greater_than: 0)
    |> unique_constraint([:plugin_id, :version])
    |> foreign_key_constraint(:plugin_id)
  end
end
