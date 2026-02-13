defmodule SentinelCp.Repo.Migrations.AddDiscoverySourceConfig do
  use Ecto.Migration

  def up do
    # SQLite doesn't support ALTER COLUMN, so we recreate the table
    # to make hostname nullable (K8s sources don't use it)
    execute("""
    CREATE TABLE discovery_sources_new (
      id TEXT PRIMARY KEY,
      source_type TEXT NOT NULL DEFAULT 'dns_srv',
      hostname TEXT,
      config TEXT DEFAULT '{}',
      sync_interval_seconds INTEGER DEFAULT 60,
      auto_sync INTEGER DEFAULT 1,
      last_synced_at TEXT,
      last_sync_status TEXT DEFAULT 'pending',
      last_sync_error TEXT,
      last_sync_targets_count INTEGER DEFAULT 0,
      upstream_group_id TEXT NOT NULL REFERENCES upstream_groups(id) ON DELETE CASCADE,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO discovery_sources_new
    SELECT id, source_type, hostname, '{}', sync_interval_seconds, auto_sync,
           last_synced_at, last_sync_status, last_sync_error, last_sync_targets_count,
           upstream_group_id, project_id, inserted_at, updated_at
    FROM discovery_sources
    """)

    execute("DROP TABLE discovery_sources")
    execute("ALTER TABLE discovery_sources_new RENAME TO discovery_sources")

    # Recreate indexes
    create index(:discovery_sources, [:project_id])
    create unique_index(:discovery_sources, [:upstream_group_id])
  end

  def down do
    execute("""
    CREATE TABLE discovery_sources_old (
      id TEXT PRIMARY KEY,
      source_type TEXT NOT NULL DEFAULT 'dns_srv',
      hostname TEXT NOT NULL,
      sync_interval_seconds INTEGER DEFAULT 60,
      auto_sync INTEGER DEFAULT 1,
      last_synced_at TEXT,
      last_sync_status TEXT DEFAULT 'pending',
      last_sync_error TEXT,
      last_sync_targets_count INTEGER DEFAULT 0,
      upstream_group_id TEXT NOT NULL REFERENCES upstream_groups(id) ON DELETE CASCADE,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO discovery_sources_old
    SELECT id, source_type, COALESCE(hostname, ''), sync_interval_seconds, auto_sync,
           last_synced_at, last_sync_status, last_sync_error, last_sync_targets_count,
           upstream_group_id, project_id, inserted_at, updated_at
    FROM discovery_sources
    """)

    execute("DROP TABLE discovery_sources")
    execute("ALTER TABLE discovery_sources_old RENAME TO discovery_sources")

    create index(:discovery_sources, [:project_id])
    create unique_index(:discovery_sources, [:upstream_group_id])
  end
end
