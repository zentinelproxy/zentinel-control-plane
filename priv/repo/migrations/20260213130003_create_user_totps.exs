defmodule ZentinelCp.Repo.Migrations.CreateUserTotps do
  use Ecto.Migration

  def change do
    create table(:user_totps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :secret, :binary, null: false
      add :recovery_codes, {:array, :string}, default: []
      add :verified_at, :utc_datetime
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_totps, [:user_id])

    # Per-org MFA enforcement policy
    alter table(:orgs) do
      add :mfa_policy, :string, default: "optional"
      add :mfa_grace_period_days, :integer, default: 14
      add :mfa_enforced_at, :utc_datetime
    end
  end
end
