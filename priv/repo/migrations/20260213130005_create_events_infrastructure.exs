defmodule ZentinelCp.Repo.Migrations.CreateEventsInfrastructure do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all)
      add :emitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:type])
    create index(:events, [:project_id])
    create index(:events, [:org_id])
    create index(:events, [:emitted_at])

    create table(:notification_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, null: false, default: %{}
      add :enabled, :boolean, default: true
      add :signing_secret, :string

      timestamps(type: :utc_datetime)
    end

    create index(:notification_channels, [:project_id])
    create unique_index(:notification_channels, [:project_id, :name])

    create table(:notification_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :event_pattern, :string, null: false

      add :channel_id,
          references(:notification_channels, type: :binary_id, on_delete: :delete_all),
          null: false

      add :enabled, :boolean, default: true
      add :filter, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:notification_rules, [:project_id])
    create index(:notification_rules, [:channel_id])

    create table(:delivery_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false

      add :channel_id,
          references(:notification_channels, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :string, null: false, default: "pending"
      add :http_status, :integer
      add :latency_ms, :integer
      add :error, :text
      add :attempt_number, :integer, null: false, default: 1
      add :next_retry_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:delivery_attempts, [:event_id])
    create index(:delivery_attempts, [:channel_id])
    create index(:delivery_attempts, [:status])
  end
end
