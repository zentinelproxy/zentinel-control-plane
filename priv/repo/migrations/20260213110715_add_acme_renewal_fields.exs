defmodule SentinelCp.Repo.Migrations.AddAcmeRenewalFields do
  use Ecto.Migration

  def change do
    alter table(:certificates) do
      add :acme_account_key_encrypted, :binary
      add :last_renewal_at, :utc_datetime
      add :last_renewal_error, :string
    end
  end
end
