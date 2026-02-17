defmodule ZentinelCp.Repo.Migrations.CreateCertificates do
  use Ecto.Migration

  def change do
    create table(:certificates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :domain, :string, null: false
      add :san_domains, {:array, :string}, default: []
      add :cert_pem, :text, null: false
      add :key_pem_encrypted, :binary, null: false
      add :ca_chain_pem, :text
      add :issuer, :string
      add :not_before, :utc_datetime
      add :not_after, :utc_datetime
      add :fingerprint_sha256, :string
      add :auto_renew, :boolean, default: false
      add :acme_config, :map, default: %{}
      add :status, :string, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:certificates, [:project_id])
    create unique_index(:certificates, [:project_id, :slug])
    create index(:certificates, [:not_after])

    alter table(:services) do
      add :certificate_id,
          references(:certificates, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
