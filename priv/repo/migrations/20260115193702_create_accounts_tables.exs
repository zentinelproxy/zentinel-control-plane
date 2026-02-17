defmodule ZentinelCp.Repo.Migrations.CreateAccountsTables do
  use Ecto.Migration

  def change do
    # Users table
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :role, :string, null: false, default: "reader"
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    # API Keys table
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      # Will be a FK after projects table exists
      add :project_id, :binary_id
      add :name, :string, null: false
      add :key_hash, :string, null: false
      # First 8 chars for identification
      add :key_prefix, :string, null: false
      add :scopes, {:array, :string}, default: []
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:api_keys, [:user_id])
    create index(:api_keys, [:project_id])
    create index(:api_keys, [:key_hash])

    # User tokens table (for sessions, password reset, etc.)
    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
