defmodule ZentinelCp.Analytics.WafBaseline do
  @moduledoc """
  Schema for WAF event statistical baselines.

  Stores mean and standard deviation for various WAF metrics to enable
  anomaly detection via z-score analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @metric_types ~w(total_blocks blocks_by_rule unique_ips block_rate)
  @periods ~w(hourly daily)

  schema "waf_baselines" do
    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :service, ZentinelCp.Services.Service

    field :metric_type, :string
    field :period, :string, default: "hourly"
    field :mean, :float
    field :stddev, :float
    field :sample_count, :integer, default: 0
    field :last_computed_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(baseline, attrs) do
    baseline
    |> cast(attrs, [
      :project_id,
      :service_id,
      :metric_type,
      :period,
      :mean,
      :stddev,
      :sample_count,
      :last_computed_at,
      :metadata
    ])
    |> validate_required([:project_id, :metric_type])
    |> validate_inclusion(:metric_type, @metric_types)
    |> validate_inclusion(:period, @periods)
    |> unique_constraint([:project_id, :service_id, :metric_type, :period],
      name: :waf_baselines_project_service_metric_period
    )
    |> foreign_key_constraint(:project_id)
  end

  def metric_types, do: @metric_types
end
