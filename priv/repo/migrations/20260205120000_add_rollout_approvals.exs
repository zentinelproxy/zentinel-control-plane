defmodule ZentinelCp.Repo.Migrations.AddRolloutApprovals do
  use Ecto.Migration

  def change do
    alter table(:rollouts) do
      add :approval_state, :string, null: false, default: "not_required"
      add :rejection_comment, :string
      add :rejected_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :rejected_at, :utc_datetime
    end

    create index(:rollouts, [:approval_state])

    create table(:rollout_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :rollout_id, references(:rollouts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :approved_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:rollout_approvals, [:rollout_id, :user_id])
    create index(:rollout_approvals, [:rollout_id])
  end
end
