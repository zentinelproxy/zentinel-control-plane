defmodule ZentinelCp.Analytics.MetricRollup do
  @moduledoc """
  Schema for pre-aggregated metric rollups.

  Rollups store hourly and daily aggregations of service metrics,
  enabling fast queries over long time ranges without scanning raw data.

  ## Periods
  - `hourly` — one record per service per hour
  - `daily` — one record per service per day
  - `monthly` — one record per service per month
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @periods ~w(hourly daily monthly)

  schema "metric_rollups" do
    field :period, :string
    field :period_start, :utc_datetime
    field :request_count, :integer, default: 0
    field :error_count, :integer, default: 0
    field :latency_p50_ms, :integer
    field :latency_p95_ms, :integer
    field :latency_p99_ms, :integer
    field :bandwidth_in_bytes, :integer, default: 0
    field :bandwidth_out_bytes, :integer, default: 0
    field :status_2xx, :integer, default: 0
    field :status_3xx, :integer, default: 0
    field :status_4xx, :integer, default: 0
    field :status_5xx, :integer, default: 0

    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(rollup, attrs) do
    rollup
    |> cast(attrs, [
      :service_id,
      :project_id,
      :period,
      :period_start,
      :request_count,
      :error_count,
      :latency_p50_ms,
      :latency_p95_ms,
      :latency_p99_ms,
      :bandwidth_in_bytes,
      :bandwidth_out_bytes,
      :status_2xx,
      :status_3xx,
      :status_4xx,
      :status_5xx
    ])
    |> validate_required([:service_id, :project_id, :period, :period_start])
    |> validate_inclusion(:period, @periods)
    |> unique_constraint([:service_id, :period, :period_start])
    |> foreign_key_constraint(:service_id)
    |> foreign_key_constraint(:project_id)
  end

  def periods, do: @periods
end
