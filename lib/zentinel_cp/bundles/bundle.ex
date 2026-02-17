defmodule ZentinelCp.Bundles.Bundle do
  @moduledoc """
  Bundle schema representing an immutable, content-addressed configuration artifact.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending compiling compiled failed superseded revoked)
  @risk_levels ~w(low medium high)
  @source_types ~w(api git)

  schema "bundles" do
    field :version, :string
    field :status, :string, default: "pending"
    field :checksum, :string
    field :size_bytes, :integer
    field :storage_key, :string
    field :config_source, :string
    field :manifest, :map, default: %{}
    field :compiler_output, :string
    field :risk_level, :string, default: "low"
    field :risk_reasons, {:array, :string}, default: []
    field :signature, :binary
    field :signing_key_id, :string
    field :created_by_id, :binary_id
    field :source_type, :string, default: "api"
    field :source_ref, :string
    field :source_branch, :string
    field :source_repo, :string
    field :sbom, :map
    field :sbom_format, :string

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :parent_bundle, ZentinelCp.Bundles.Bundle

    timestamps(type: :utc_datetime)
  end

  def create_changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [
      :version,
      :config_source,
      :project_id,
      :created_by_id,
      :risk_level,
      :source_type,
      :source_ref,
      :source_branch,
      :source_repo,
      :parent_bundle_id
    ])
    |> validate_required([:version, :config_source, :project_id])
    |> validate_length(:version, min: 1, max: 100)
    |> validate_inclusion(:risk_level, @risk_levels)
    |> validate_inclusion(:source_type, @source_types)
    |> put_change(:status, "pending")
    |> unique_constraint([:project_id, :version])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_bundle_id)
  end

  def compilation_changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [
      :status,
      :checksum,
      :size_bytes,
      :storage_key,
      :manifest,
      :compiler_output,
      :signature,
      :signing_key_id,
      :sbom,
      :sbom_format,
      :risk_level,
      :risk_reasons
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:risk_level, @risk_levels)
  end

  def status_changeset(bundle, status) do
    bundle
    |> change(status: status)
    |> validate_inclusion(:status, @statuses)
  end
end
