defmodule ZentinelCp.Services.OpenApiSpec do
  @moduledoc """
  Schema for stored OpenAPI specification files.

  Tracks imported OpenAPI specs for change detection on re-import
  and documentation linkage to services.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "openapi_specs" do
    field :name, :string
    field :file_name, :string
    field :openapi_version, :string
    field :spec_version, :string
    field :spec_data, :map
    field :checksum, :string
    field :paths_count, :integer, default: 0
    field :status, :string, default: "active"

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :services, ZentinelCp.Services.Service, foreign_key: :openapi_spec_id

    timestamps(type: :utc_datetime)
  end

  def changeset(spec, attrs) do
    spec
    |> cast(attrs, [
      :name,
      :file_name,
      :openapi_version,
      :spec_version,
      :spec_data,
      :checksum,
      :paths_count,
      :status,
      :project_id
    ])
    |> validate_required([:name, :file_name, :spec_data, :checksum, :project_id])
    |> validate_inclusion(:status, ~w(active superseded))
    |> foreign_key_constraint(:project_id)
  end
end
