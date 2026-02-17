defmodule ZentinelCp.Repo.Migrations.CreateRolloutsTables do
  use Ecto.Migration

  def change do
    create table(:rollouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :bundle_id, references(:bundles, type: :binary_id, on_delete: :restrict), null: false
      add :target_selector, :map, null: false
      add :strategy, :string, null: false, default: "rolling"
      add :batch_size, :integer, null: false, default: 1
      add :max_unavailable, :integer, null: false, default: 0
      add :progress_deadline_seconds, :integer, null: false, default: 600
      add :health_gates, :map, default: %{"heartbeat_healthy" => true}
      add :state, :string, null: false, default: "pending"
      add :created_by_id, :binary_id
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error, :map

      timestamps(type: :utc_datetime)
    end

    create index(:rollouts, [:project_id])
    create index(:rollouts, [:state])

    create table(:rollout_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :rollout_id, references(:rollouts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :step_index, :integer, null: false
      add :node_ids, {:array, :string}, null: false, default: []
      add :state, :string, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rollout_steps, [:rollout_id, :step_index])

    create table(:node_bundle_statuses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false

      add :rollout_id, references(:rollouts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :bundle_id, references(:bundles, type: :binary_id, on_delete: :restrict), null: false
      add :state, :string, null: false, default: "pending"
      add :reason, :string
      add :staged_at, :utc_datetime
      add :activated_at, :utc_datetime
      add :verified_at, :utc_datetime
      add :last_report_at, :utc_datetime
      add :error, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_bundle_statuses, [:node_id, :rollout_id])
    create index(:node_bundle_statuses, [:rollout_id])
  end
end
