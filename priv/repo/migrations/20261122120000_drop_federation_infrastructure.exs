defmodule ZentinelCp.Repo.Migrations.DropFederationInfrastructure do
  use Ecto.Migration

  # Federation was a stub and is removed in 0.3.0. This drops everything
  # 20260213130009_create_federation_infrastructure created, along with any
  # data in it. `down` recreates the schema empty so a rollback to 0.2.x code
  # still boots; the dropped rows are not restored.

  def up do
    # Scheduled runs of the removed worker would fail with an unknown worker.
    execute("DELETE FROM oban_jobs WHERE worker = 'ZentinelCp.Federation.SyncWorker'")

    drop table(:bundle_replications)
    drop table(:regional_storages)
    drop table(:federation_peers)

    alter table(:rollouts) do
      remove :region
      remove :region_strategy
      remove :region_order
      remove :current_region_index
    end
  end

  def down do
    create table(:federation_peers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :url, :string, null: false
      add :role, :string, null: false, default: "spoke"
      add :region, :string, null: false
      add :tls_cert_pem, :text
      add :api_key_hash, :string
      add :sync_status, :string, null: false, default: "pending"
      add :last_sync_at, :utc_datetime
      add :last_sync_error, :text
      add :metadata, :map, default: %{}
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:federation_peers, [:url])
    create index(:federation_peers, [:region])

    create table(:regional_storages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :peer_id, references(:federation_peers, type: :binary_id, on_delete: :delete_all)
      add :region, :string, null: false
      add :bucket, :string, null: false
      add :endpoint, :string, null: false
      add :access_key_id, :string
      add :secret_access_key_encrypted, :binary
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:regional_storages, [:region])

    create table(:bundle_replications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bundle_id, references(:bundles, type: :binary_id, on_delete: :delete_all), null: false
      add :region, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :replicated_at, :utc_datetime
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:bundle_replications, [:bundle_id])
    create unique_index(:bundle_replications, [:bundle_id, :region])

    alter table(:rollouts) do
      add :region, :string
      add :region_strategy, :string
      add :region_order, {:array, :string}, default: []
      add :current_region_index, :integer, default: 0
    end
  end
end
