defmodule ZentinelCp.Repo.Migrations.AddAuditLogChainFields do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add :previous_hash, :string
      add :entry_hash, :string
    end

    create table(:audit_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sequence_number, :integer, null: false
      add :last_entry_id, references(:audit_logs, type: :binary_id)
      add :last_entry_hash, :string, null: false
      add :digest, :string, null: false
      add :signature, :string, null: false
      add :entries_count, :integer, null: false
      add :project_id, :binary_id

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_checkpoints, [:sequence_number])
    create index(:audit_checkpoints, [:project_id])
  end
end
