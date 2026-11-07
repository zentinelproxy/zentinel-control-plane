defmodule ZentinelCp.Repo.Migrations.AddAuditChainSequence do
  use Ecto.Migration

  def up do
    alter table(:audit_logs) do
      add :chain_sequence, :bigint
      add :hash_version, :integer
    end

    flush()

    # Existing entries keep version NULL: only their links can be verified.
    execute("""
    UPDATE audit_logs SET chain_sequence = numbered.sequence
    FROM (
      SELECT id, row_number() OVER (ORDER BY inserted_at, id) AS sequence
      FROM audit_logs WHERE entry_hash IS NOT NULL
    ) AS numbered
    WHERE audit_logs.id = numbered.id
    """)

    create index(:audit_logs, [:chain_sequence])
  end

  def down do
    drop index(:audit_logs, [:chain_sequence])

    alter table(:audit_logs) do
      remove :chain_sequence
      remove :hash_version
    end
  end
end
