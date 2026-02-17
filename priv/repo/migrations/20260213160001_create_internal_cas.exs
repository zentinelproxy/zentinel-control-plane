defmodule ZentinelCp.Repo.Migrations.CreateInternalCas do
  use Ecto.Migration

  def change do
    create table(:internal_cas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :ca_cert_pem, :text, null: false
      add :ca_key_encrypted, :binary, null: false
      add :key_algorithm, :string, null: false, default: "EC-P384"
      add :subject_cn, :string, null: false
      add :not_before, :utc_datetime
      add :not_after, :utc_datetime
      add :fingerprint_sha256, :string
      add :next_serial, :integer, null: false, default: 1
      add :crl_pem, :text
      add :crl_updated_at, :utc_datetime
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:internal_cas, [:project_id])
    create index(:internal_cas, [:status])

    create table(:issued_certificates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :internal_ca_id, references(:internal_cas, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :serial_number, :integer, null: false
      add :subject_cn, :string, null: false
      add :subject_ou, :string
      add :cert_pem, :text, null: false
      add :key_pem_encrypted, :binary, null: false
      add :not_before, :utc_datetime
      add :not_after, :utc_datetime
      add :fingerprint_sha256, :string
      add :key_usage, :string, null: false, default: "clientAuth"
      add :status, :string, null: false, default: "active"
      add :revoked_at, :utc_datetime
      add :revoke_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:issued_certificates, [:internal_ca_id])
    create unique_index(:issued_certificates, [:internal_ca_id, :serial_number])
    create unique_index(:issued_certificates, [:internal_ca_id, :slug])
  end
end
