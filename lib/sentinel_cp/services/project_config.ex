defmodule SentinelCp.Services.ProjectConfig do
  @moduledoc """
  ProjectConfig schema storing global proxy settings for a project.

  Maps to the `settings {}` block in generated KDL configuration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @log_levels ~w(trace debug info warn error)

  schema "project_configs" do
    field :log_level, :string, default: "info"
    field :metrics_port, :integer, default: 9090
    field :custom_settings, :map, default: %{}
    field :default_cors, :map, default: %{}
    field :default_compression, :map, default: %{}
    field :global_access_control, :map, default: %{}
    field :default_security, :map, default: %{}

    belongs_to :project, SentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :log_level,
      :metrics_port,
      :custom_settings,
      :default_cors,
      :default_compression,
      :global_access_control,
      :default_security,
      :project_id
    ])
    |> validate_required([:project_id])
    |> validate_inclusion(:log_level, @log_levels)
    |> validate_number(:metrics_port, greater_than: 0, less_than: 65536)
    |> unique_constraint(:project_id)
    |> foreign_key_constraint(:project_id)
  end
end
