defmodule ZentinelCp.Repo.Migrations.AddMultiOrgSupport do
  use Ecto.Migration

  def change do
    # Organizations table
    create table(:orgs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orgs, [:slug])

    # Org memberships (join table for multi-org users)
    create table(:org_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :role, :string, null: false, default: "reader"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:org_memberships, [:org_id, :user_id])
    create index(:org_memberships, [:user_id])

    # Add org_id to projects
    alter table(:projects) do
      add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict)
    end

    create index(:projects, [:org_id])

    # Make project slug unique within org (not globally)
    drop_if_exists unique_index(:projects, [:slug])
    create unique_index(:projects, [:org_id, :slug])

    # Add org_id to audit_logs
    alter table(:audit_logs) do
      add :org_id, :binary_id
    end

    create index(:audit_logs, [:org_id])
  end
end
