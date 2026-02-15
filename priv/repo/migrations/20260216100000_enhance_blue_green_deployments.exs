defmodule SentinelCp.Repo.Migrations.EnhanceBlueGreenDeployments do
  use Ecto.Migration

  def change do
    alter table(:rollouts) do
      add :blue_green_config, :map
      add :traffic_step_index, :integer, default: 0
    end

    alter table(:rollout_steps) do
      add :validated_at, :utc_datetime
      add :health_gate_failure_since, :utc_datetime
    end

    alter table(:rollout_templates) do
      add :auto_rollback, :boolean, default: false
      add :rollback_threshold, :integer, default: 50
      add :canary_analysis_config, :map
      add :blue_green_config, :map
      add :validation_period_seconds, :integer, default: 300
    end
  end
end
