defmodule ZentinelCp.Repo.Migrations.AddSsoFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sso_provider_type, :string
      add :sso_provider_id, :binary_id
      add :sso_subject, :string
      add :sso_provisioned_at, :utc_datetime
    end

    create index(:users, [:sso_provider_type, :sso_provider_id, :sso_subject],
             name: :users_sso_lookup_idx
           )
  end
end
