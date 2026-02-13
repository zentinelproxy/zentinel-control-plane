defmodule SentinelCp.Repo.Migrations.CreateTrustStores do
  use Ecto.Migration

  def change do
    create table(:trust_stores, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :certificates_pem, :text, null: false
      add :cert_count, :integer, null: false, default: 0
      add :subjects, {:array, :string}, default: []
      add :earliest_expiry, :utc_datetime
      add :latest_expiry, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:trust_stores, [:project_id])
    create unique_index(:trust_stores, [:project_id, :slug])
    create index(:trust_stores, [:earliest_expiry])

    alter table(:upstream_groups) do
      add :trust_store_id, references(:trust_stores, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
