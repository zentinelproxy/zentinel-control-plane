defmodule ZentinelCp.Rollouts.RolloutTemplate do
  @moduledoc """
  Schema for rollout templates - reusable configurations for creating rollouts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @strategies ~w(rolling all_at_once blue_green canary)
  @valid_health_gate_keys ~w(heartbeat_healthy max_error_rate max_latency_ms max_cpu_percent max_memory_percent)

  schema "rollout_templates" do
    field :name, :string
    field :description, :string
    field :is_default, :boolean, default: false
    field :target_selector, :map
    field :strategy, :string, default: "rolling"
    field :batch_size, :integer, default: 1
    field :max_unavailable, :integer, default: 0
    field :progress_deadline_seconds, :integer, default: 600
    field :health_gates, :map, default: %{"heartbeat_healthy" => true}
    field :created_by_id, :binary_id
    field :auto_rollback, :boolean, default: false
    field :rollback_threshold, :integer, default: 50
    field :canary_analysis_config, :map
    field :blue_green_config, :map
    field :validation_period_seconds, :integer, default: 300

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new template.
  """
  def create_changeset(template, attrs) do
    template
    |> cast(attrs, [
      :project_id,
      :name,
      :description,
      :is_default,
      :target_selector,
      :strategy,
      :batch_size,
      :max_unavailable,
      :progress_deadline_seconds,
      :health_gates,
      :created_by_id,
      :auto_rollback,
      :rollback_threshold,
      :canary_analysis_config,
      :blue_green_config,
      :validation_period_seconds
    ])
    |> validate_required([:project_id, :name])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:strategy, @strategies)
    |> validate_number(:batch_size, greater_than: 0)
    |> validate_number(:max_unavailable, greater_than_or_equal_to: 0)
    |> validate_number(:progress_deadline_seconds, greater_than: 0)
    |> validate_target_selector()
    |> validate_health_gates()
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a template.
  """
  def update_changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name,
      :description,
      :is_default,
      :target_selector,
      :strategy,
      :batch_size,
      :max_unavailable,
      :progress_deadline_seconds,
      :health_gates,
      :auto_rollback,
      :rollback_threshold,
      :canary_analysis_config,
      :blue_green_config,
      :validation_period_seconds
    ])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:strategy, @strategies)
    |> validate_number(:batch_size, greater_than: 0)
    |> validate_number(:max_unavailable, greater_than_or_equal_to: 0)
    |> validate_number(:progress_deadline_seconds, greater_than: 0)
    |> validate_target_selector()
    |> validate_health_gates()
    |> unique_constraint([:project_id, :name])
  end

  @doc """
  Converts a template to attributes suitable for creating a rollout.
  Does not include project_id, bundle_id, or created_by_id - those must be set separately.
  """
  def to_rollout_attrs(%__MODULE__{} = template) do
    base = %{
      target_selector: template.target_selector,
      strategy: template.strategy,
      batch_size: template.batch_size,
      max_unavailable: template.max_unavailable,
      progress_deadline_seconds: template.progress_deadline_seconds,
      health_gates: template.health_gates,
      auto_rollback: template.auto_rollback,
      rollback_threshold: template.rollback_threshold,
      validation_period_seconds: template.validation_period_seconds
    }

    base
    |> maybe_put(:canary_analysis_config, template.canary_analysis_config)
    |> maybe_put(:blue_green_config, template.blue_green_config)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_target_selector(changeset) do
    validate_change(changeset, :target_selector, fn :target_selector, selector ->
      case selector do
        nil ->
          []

        %{"type" => "all"} ->
          []

        %{"type" => "labels", "labels" => labels} when is_map(labels) and map_size(labels) > 0 ->
          []

        %{"type" => "node_ids", "node_ids" => ids} when is_list(ids) and length(ids) > 0 ->
          []

        _ ->
          [
            target_selector:
              "must be {type: all}, {type: labels, labels: {...}}, or {type: node_ids, node_ids: [...]}"
          ]
      end
    end)
  end

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
end
