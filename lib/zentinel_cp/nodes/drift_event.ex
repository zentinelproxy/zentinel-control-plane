defmodule ZentinelCp.Nodes.DriftEvent do
  @moduledoc """
  Schema for drift events.

  A drift event is created when a node's active_bundle_id differs from its
  expected_bundle_id. The expected bundle is set when a rollout step completes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @resolutions ~w(auto_corrected manual rollout_started rollout_completed)
  @severities ~w(low medium high critical)

  schema "drift_events" do
    field :expected_bundle_id, :binary_id
    field :actual_bundle_id, :binary_id
    field :detected_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :resolution, :string
    field :severity, :string, default: "medium"
    field :diff_stats, :map

    belongs_to :node, ZentinelCp.Nodes.Node
    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid resolutions.
  """
  def resolutions, do: @resolutions

  @doc """
  Returns the list of valid severities.
  """
  def severities, do: @severities

  @doc """
  Changeset for creating a new drift event.
  """
  def create_changeset(drift_event, attrs) do
    drift_event
    |> cast(attrs, [
      :node_id,
      :project_id,
      :expected_bundle_id,
      :actual_bundle_id,
      :detected_at,
      :severity,
      :diff_stats
    ])
    |> validate_required([:node_id, :project_id, :expected_bundle_id, :detected_at])
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for resolving a drift event.
  """
  def resolve_changeset(drift_event, resolution) do
    drift_event
    |> change(%{
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      resolution: resolution
    })
    |> validate_inclusion(:resolution, @resolutions)
  end

  @doc """
  Calculates severity based on diff stats.

  - critical: >50 changes or no actual bundle (node completely unconfigured)
  - high: >20 changes
  - medium: >5 changes
  - low: <=5 changes
  """
  def calculate_severity(nil, _actual_bundle_id), do: "medium"

  def calculate_severity(_diff_stats, nil), do: "critical"

  def calculate_severity(%{} = diff_stats, _actual_bundle_id) do
    total_changes =
      Map.get(diff_stats, :additions, 0) +
        Map.get(diff_stats, :deletions, 0) +
        Map.get(diff_stats, "additions", 0) +
        Map.get(diff_stats, "deletions", 0)

    cond do
      total_changes > 50 -> "critical"
      total_changes > 20 -> "high"
      total_changes > 5 -> "medium"
      true -> "low"
    end
  end
end
