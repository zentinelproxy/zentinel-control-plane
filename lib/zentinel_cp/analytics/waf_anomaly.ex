defmodule ZentinelCp.Analytics.WafAnomaly do
  @moduledoc """
  Schema for WAF anomaly detection results.

  Anomalies are detected by comparing current WAF event metrics against
  statistical baselines (z-score analysis).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @anomaly_types ~w(spike new_vector ip_burst rate_change)
  @severities ~w(critical high medium low)
  @statuses ~w(active acknowledged resolved false_positive)

  schema "waf_anomalies" do
    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :acknowledged_by_user, ZentinelCp.Accounts.User, foreign_key: :acknowledged_by

    field :anomaly_type, :string
    field :severity, :string, default: "medium"
    field :status, :string, default: "active"
    field :detected_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :description, :string
    field :observed_value, :float
    field :expected_mean, :float
    field :expected_stddev, :float
    field :deviation_sigma, :float
    field :evidence, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def create_changeset(anomaly, attrs) do
    anomaly
    |> cast(attrs, [
      :project_id,
      :service_id,
      :anomaly_type,
      :severity,
      :detected_at,
      :description,
      :observed_value,
      :expected_mean,
      :expected_stddev,
      :deviation_sigma,
      :evidence
    ])
    |> validate_required([:project_id, :anomaly_type, :detected_at])
    |> validate_inclusion(:anomaly_type, @anomaly_types)
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:project_id)
  end

  def acknowledge_changeset(anomaly, user_id) do
    anomaly
    |> change(%{status: "acknowledged", acknowledged_by: user_id})
  end

  def resolve_changeset(anomaly) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    anomaly
    |> change(%{status: "resolved", resolved_at: now})
  end

  def false_positive_changeset(anomaly, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    anomaly
    |> change(%{status: "false_positive", resolved_at: now, acknowledged_by: user_id})
  end

  def anomaly_types, do: @anomaly_types
  def severities, do: @severities
  def statuses, do: @statuses
end
