defmodule ZentinelCp.Accounts.ApiKey do
  @moduledoc """
  API Key schema for programmatic access.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @key_prefix_length 8
  @key_length 32

  schema "api_keys" do
    field :name, :string
    field :key, :string, virtual: true, redact: true
    field :key_hash, :string, redact: true
    field :key_prefix, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, ZentinelCp.Accounts.User
    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Generates a new API key and returns {raw_key, changeset}.
  The raw key should be shown to the user once and never stored.
  """
  def create_changeset(api_key, attrs) do
    raw_key = generate_key()
    key_hash = hash_key(raw_key)
    key_prefix = String.slice(raw_key, 0, @key_prefix_length)

    api_key
    |> cast(attrs, [:name, :scopes, :expires_at, :user_id, :project_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> put_change(:key, raw_key)
    |> put_change(:key_hash, key_hash)
    |> put_change(:key_prefix, key_prefix)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for revoking an API key.
  """
  def revoke_changeset(api_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(api_key, revoked_at: now)
  end

  @doc """
  Changeset for updating last_used_at.
  """
  def touch_changeset(api_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(api_key, last_used_at: now)
  end

  @doc """
  Verifies an API key against its hash.
  """
  def valid_key?(api_key, raw_key) do
    hash_key(raw_key) == api_key.key_hash
  end

  @doc """
  Checks if the API key is active (not revoked, not expired).
  """
  def active?(%__MODULE__{revoked_at: revoked_at, expires_at: expires_at}) do
    now = DateTime.utc_now()

    is_nil(revoked_at) and
      (is_nil(expires_at) or DateTime.compare(expires_at, now) == :gt)
  end

  @doc """
  Generates a secure random API key.
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_length)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Hashes an API key for storage.
  """
  def hash_key(key) do
    :crypto.hash(:sha256, key)
    |> Base.encode64()
  end
end
