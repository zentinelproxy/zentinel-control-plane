defmodule ZentinelCp.Repo.Migrations.AddJwtNodeAuth do
  use Ecto.Migration

  def change do
    # Org signing keys for JWT issuance (Ed25519)
    create table(:org_signing_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :key_id, :string, null: false
      add :public_key, :binary, null: false
      add :private_key_encrypted, :binary, null: false
      add :algorithm, :string, null: false, default: "Ed25519"
      add :active, :boolean, null: false, default: true
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:org_signing_keys, [:key_id])
    create index(:org_signing_keys, [:org_id])

    # Token tracking fields on nodes
    alter table(:nodes) do
      add :token_issued_at, :utc_datetime
      add :token_expires_at, :utc_datetime
      add :auth_method, :string, default: "static_key"
    end
  end
end
