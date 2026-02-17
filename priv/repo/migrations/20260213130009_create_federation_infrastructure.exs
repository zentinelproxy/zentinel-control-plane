defmodule ZentinelCp.Repo.Migrations.CreateFederationInfrastructure do
  use Ecto.Migration

  def change do
    # Federation peers (hub-spoke topology)
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

    # Regional storage configuration
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

    # Bundle replication tracking
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

    # Cross-region rollout configuration
    alter table(:rollouts) do
      add :region, :string
      add :region_strategy, :string
      add :region_order, {:array, :string}, default: []
      add :current_region_index, :integer, default: 0
    end
  end
end
