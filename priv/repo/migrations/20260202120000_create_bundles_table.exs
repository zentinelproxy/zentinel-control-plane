defmodule ZentinelCp.Repo.Migrations.CreateBundlesTable do
  use Ecto.Migration

  def change do
    create table(:bundles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :version, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :checksum, :string
      add :size_bytes, :integer
      add :storage_key, :string
      add :config_source, :text, null: false
      add :manifest, :map, default: %{}
      add :compiler_output, :text
      add :risk_level, :string, default: "low"
      add :created_by_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:bundles, [:project_id])
    create index(:bundles, [:status])
    create index(:bundles, [:project_id, :version], unique: true)
  end
end
