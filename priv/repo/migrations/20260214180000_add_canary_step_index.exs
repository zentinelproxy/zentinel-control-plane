defmodule ZentinelCp.Repo.Migrations.AddCanaryStepIndex do
  use Ecto.Migration

  def change do
    alter table(:rollouts) do
      add :canary_step_index, :integer, default: 0
    end
  end
end
