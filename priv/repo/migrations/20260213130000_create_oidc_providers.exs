defmodule ZentinelCp.Repo.Migrations.CreateOidcProviders do
  use Ecto.Migration

  def change do
    create table(:oidc_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :issuer, :string, null: false
      add :client_id, :string, null: false
      add :client_secret_encrypted, :binary, null: false
      add :discovery_url, :string, null: false
      add :scopes, {:array, :string}, default: ["openid", "email", "profile"]
      add :default_role, :string, default: "reader"
      add :auto_provision, :boolean, default: true
      add :group_mapping, :map, default: %{}
      add :enabled, :boolean, default: true
      add :fallback_to_password, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:oidc_providers, [:org_id])
    create unique_index(:oidc_providers, [:org_id, :issuer])
  end
end
