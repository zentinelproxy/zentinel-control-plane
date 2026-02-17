defmodule ZentinelCp.Repo.Migrations.CreateVaultConfigs do
  use Ecto.Migration

  def change do
    create table(:vault_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, default: false
      add :vault_addr, :string, null: false
      add :auth_method, :string, default: "token"
      add :auth_config, :binary
      add :mount_path, :string, default: "secret"
      add :base_path, :string
      add :namespace, :string
      add :last_connected_at, :utc_datetime
      add :connection_status, :string, default: "unknown"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vault_configs, [:project_id])
  end
end
