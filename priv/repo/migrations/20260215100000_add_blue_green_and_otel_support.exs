defmodule SentinelCp.Repo.Migrations.AddBlueGreenAndOtelSupport do
  use Ecto.Migration

  def change do
    alter table(:rollout_steps) do
      add :deployment_slot, :string
      add :traffic_weight, :integer
    end
  end
end
