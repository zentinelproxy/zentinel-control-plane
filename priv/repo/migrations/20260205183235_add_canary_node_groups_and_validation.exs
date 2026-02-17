defmodule ZentinelCp.Repo.Migrations.AddCanaryNodeGroupsAndValidation do
  use Ecto.Migration

  def change do
    # Feature 1: Canary deployments - add percentage-based batch size
    alter table(:rollouts) do
      add :batch_percentage, :integer
      add :auto_rollback, :boolean, default: false
      add :rollback_threshold, :integer, default: 50
    end

    # Feature 2: Node groups
    create table(:node_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :color, :string, default: "#6366f1"

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_groups, [:project_id, :name])
    create index(:node_groups, [:project_id])

    create table(:node_group_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false

      add :node_group_id, references(:node_groups, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_group_memberships, [:node_id, :node_group_id])
    create index(:node_group_memberships, [:node_group_id])

    # Feature 4: Bundle version pinning
    alter table(:nodes) do
      add :pinned_bundle_id, references(:bundles, type: :binary_id, on_delete: :nilify_all)
      add :min_bundle_version, :string
      add :max_bundle_version, :string
    end

    create index(:nodes, [:pinned_bundle_id])

    # Feature 5: Custom health check endpoints
    create table(:health_check_endpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :url, :string, null: false
      add :method, :string, default: "GET"
      add :timeout_ms, :integer, default: 5000
      add :expected_status, :integer, default: 200
      add :expected_body_contains, :string
      add :headers, :map, default: %{}
      add :enabled, :boolean, default: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:health_check_endpoints, [:project_id])

    # Feature 6: Config validation rules
    create table(:config_validation_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :rule_type, :string, null: false
      add :pattern, :string
      add :config, :map, default: %{}
      add :severity, :string, default: "error"
      add :enabled, :boolean, default: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:config_validation_rules, [:project_id])
    create index(:config_validation_rules, [:project_id, :rule_type])

    # Add health check endpoints reference to rollouts
    alter table(:rollouts) do
      add :custom_health_checks, {:array, :binary_id}, default: []
    end

    # Add index for audit log search
    create_if_not_exists index(:audit_logs, [:project_id, :inserted_at])
    create_if_not_exists index(:audit_logs, [:actor_type, :actor_id])
    create_if_not_exists index(:audit_logs, [:resource_type, :resource_id])
  end
end
