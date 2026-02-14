defmodule SentinelCp.Rollouts.Rollout do
  @moduledoc """
  Rollout schema representing a batched bundle deployment to nodes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(pending running paused completed cancelled failed)
  @strategies ~w(rolling all_at_once blue_green canary)
  @approval_states ~w(not_required pending_approval approved rejected)

  schema "rollouts" do
    field :target_selector, :map
    field :strategy, :string, default: "rolling"
    field :batch_size, :integer, default: 1
    field :max_unavailable, :integer, default: 0
    field :progress_deadline_seconds, :integer, default: 600
    field :health_gates, :map, default: %{"heartbeat_healthy" => true}
    field :state, :string, default: "pending"
    field :created_by_id, :binary_id
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error, :map

    # Canary deployment fields
    field :batch_percentage, :integer
    field :auto_rollback, :boolean, default: false
    field :rollback_threshold, :integer, default: 50
    field :custom_health_checks, {:array, :binary_id}, default: []

    # Approval workflow fields
    field :approval_state, :string, default: "not_required"
    field :rejection_comment, :string
    field :rejected_by_id, :binary_id
    field :rejected_at, :utc_datetime

    # Scheduled rollout
    field :scheduled_at, :utc_datetime

    # Advanced deployment fields
    field :canary_analysis_config, :map
    field :canary_analysis_results, :map
    field :canary_step_index, :integer, default: 0
    field :deployment_slot, :string
    field :validation_period_seconds, :integer, default: 300

    belongs_to :project, SentinelCp.Projects.Project
    belongs_to :bundle, SentinelCp.Bundles.Bundle
    belongs_to :environment, SentinelCp.Projects.Environment
    has_many :steps, SentinelCp.Rollouts.RolloutStep
    has_many :node_bundle_statuses, SentinelCp.Rollouts.NodeBundleStatus
    has_many :approvals, SentinelCp.Rollouts.RolloutApproval

    timestamps(type: :utc_datetime)
  end

  def create_changeset(rollout, attrs) do
    rollout
    |> cast(attrs, [
      :project_id,
      :bundle_id,
      :environment_id,
      :target_selector,
      :strategy,
      :batch_size,
      :batch_percentage,
      :max_unavailable,
      :progress_deadline_seconds,
      :health_gates,
      :created_by_id,
      :scheduled_at,
      :auto_rollback,
      :rollback_threshold,
      :custom_health_checks,
      :canary_analysis_config,
      :canary_step_index,
      :deployment_slot,
      :validation_period_seconds
    ])
    |> validate_required([:project_id, :bundle_id, :target_selector])
    |> validate_inclusion(:strategy, @strategies)
    |> validate_number(:batch_size, greater_than: 0)
    |> validate_number(:batch_percentage, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:max_unavailable, greater_than_or_equal_to: 0)
    |> validate_number(:progress_deadline_seconds, greater_than: 0)
    |> validate_number(:rollback_threshold, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_batch_config()
    |> validate_target_selector()
    |> validate_health_gates()
    |> validate_scheduled_at()
    |> put_change(:state, "pending")
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:bundle_id)
  end

  defp validate_batch_config(changeset) do
    batch_size = get_field(changeset, :batch_size)
    batch_percentage = get_field(changeset, :batch_percentage)

    cond do
      batch_percentage && batch_size && batch_size != 1 ->
        add_error(changeset, :batch_size, "cannot set both batch_size and batch_percentage")

      true ->
        changeset
    end
  end

  def state_changeset(rollout, state, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      %{state: state}
      |> maybe_set_started_at(state, rollout, now)
      |> maybe_set_completed_at(state, now)
      |> maybe_set_error(opts[:error])

    rollout
    |> change(changes)
    |> validate_inclusion(:state, @states)
  end

  defp maybe_set_started_at(changes, "running", %{started_at: nil}, now) do
    Map.put(changes, :started_at, now)
  end

  defp maybe_set_started_at(changes, _state, _rollout, _now), do: changes

  defp maybe_set_completed_at(changes, state, now) when state in ~w(completed cancelled failed) do
    Map.put(changes, :completed_at, now)
  end

  defp maybe_set_completed_at(changes, _state, _now), do: changes

  defp maybe_set_error(changes, nil), do: changes
  defp maybe_set_error(changes, error), do: Map.put(changes, :error, error)

  @valid_health_gate_keys ~w(heartbeat_healthy max_error_rate max_latency_ms max_cpu_percent max_memory_percent)

  defp validate_health_gates(changeset) do
    validate_change(changeset, :health_gates, fn :health_gates, gates ->
      unknown = Map.keys(gates) -- @valid_health_gate_keys

      if unknown == [] do
        []
      else
        [health_gates: "unknown keys: #{Enum.join(unknown, ", ")}"]
      end
    end)
  end

  defp validate_scheduled_at(changeset) do
    validate_change(changeset, :scheduled_at, fn :scheduled_at, scheduled_at ->
      now = DateTime.utc_now()

      if DateTime.compare(scheduled_at, now) == :gt do
        []
      else
        [scheduled_at: "must be in the future"]
      end
    end)
  end

  defp validate_target_selector(changeset) do
    validate_change(changeset, :target_selector, fn :target_selector, selector ->
      case selector do
        %{"type" => "all"} ->
          []

        %{"type" => "labels", "labels" => labels} when is_map(labels) and map_size(labels) > 0 ->
          []

        %{"type" => "node_ids", "node_ids" => ids} when is_list(ids) and length(ids) > 0 ->
          []

        %{"type" => "groups", "group_ids" => ids} when is_list(ids) and length(ids) > 0 ->
          []

        _ ->
          [
            target_selector:
              "must be {type: all}, {type: labels, labels: {...}}, {type: node_ids, node_ids: [...]}, or {type: groups, group_ids: [...]}"
          ]
      end
    end)
  end

  @doc """
  Changeset for updating canary analysis state.
  """
  def canary_changeset(rollout, attrs) do
    rollout
    |> cast(attrs, [:canary_step_index, :canary_analysis_results])
  end

  @doc """
  Changeset for updating approval state.
  """
  def approval_changeset(rollout, approval_state, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      if approval_state == "rejected" do
        %{
          approval_state: approval_state,
          rejection_comment: opts[:comment],
          rejected_by_id: opts[:rejected_by_id],
          rejected_at: now
        }
      else
        %{approval_state: approval_state}
      end

    rollout
    |> change(changes)
    |> validate_inclusion(:approval_state, @approval_states)
  end
end
