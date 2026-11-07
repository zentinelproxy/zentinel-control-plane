defmodule ZentinelCp.Repo.Migrations.CreateAcmeChallenges do
  use Ecto.Migration

  def change do
    create table(:acme_challenges, primary_key: false) do
      add :token, :string, primary_key: true
      add :key_authorization, :text, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create index(:acme_challenges, [:expires_at])
  end
end
