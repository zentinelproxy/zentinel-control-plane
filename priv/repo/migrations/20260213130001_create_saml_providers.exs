defmodule ZentinelCp.Repo.Migrations.CreateSamlProviders do
  use Ecto.Migration

  def change do
    create table(:saml_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :entity_id, :string, null: false
      add :sso_url, :string, null: false
      add :certificate, :text, null: false
      add :sign_requests, :boolean, default: false
      add :default_role, :string, default: "reader"
      add :auto_provision, :boolean, default: true
      add :group_mapping, :map, default: %{}
      add :enabled, :boolean, default: true
      add :fallback_to_password, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:saml_providers, [:org_id])
    create unique_index(:saml_providers, [:org_id, :entity_id])
  end
end
