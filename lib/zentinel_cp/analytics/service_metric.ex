defmodule ZentinelCp.Analytics.ServiceMetric do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "service_metrics" do
    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :project, ZentinelCp.Projects.Project

    field :period_start, :utc_datetime
    field :period_seconds, :integer, default: 60
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
    field :top_paths, :map, default: %{}
    field :top_consumers, :map, default: %{}

    timestamps()
  end

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, [
      :service_id,
      :project_id,
      :period_start,
      :period_seconds,
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
      :status_5xx,
      :top_paths,
      :top_consumers
    ])
    |> validate_required([:service_id, :project_id, :period_start])
  end
end
