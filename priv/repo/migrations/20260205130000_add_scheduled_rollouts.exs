defmodule ZentinelCp.Repo.Migrations.AddScheduledRollouts do
  use Ecto.Migration

  def change do
    alter table(:rollouts) do
      add :scheduled_at, :utc_datetime
    end

    create index(:rollouts, [:scheduled_at],
             where: "scheduled_at IS NOT NULL AND state = 'pending'"
           )
  end
end
