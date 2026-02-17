defmodule ZentinelCp.Secrets.VaultConfig do
  @moduledoc """
  Schema for Vault integration configuration per project.

  The `auth_config` field is encrypted at rest using `SecretCrypto`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ZentinelCp.Secrets.SecretCrypto

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @auth_methods ~w(token approle kubernetes)

  schema "vault_configs" do
    field :enabled, :boolean, default: false
    field :vault_addr, :string
    field :auth_method, :string, default: "token"
    field :auth_config, :binary
    field :mount_path, :string, default: "secret"
    field :base_path, :string
    field :namespace, :string
    field :last_connected_at, :utc_datetime
    field :connection_status, :string, default: "unknown"

    # Virtual field for receiving plaintext auth_config
    field :auth_config_plaintext, :map, virtual: true

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(config, attrs) do
    config
    |> cast(attrs, [
      :project_id,
      :enabled,
      :vault_addr,
      :auth_method,
      :auth_config_plaintext,
      :mount_path,
      :base_path,
      :namespace
    ])
    |> validate_required([:project_id, :vault_addr])
    |> validate_inclusion(:auth_method, @auth_methods)
    |> encrypt_auth_config()
    |> unique_constraint(:project_id)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(config, attrs) do
    config
    |> cast(attrs, [
      :enabled,
      :vault_addr,
      :auth_method,
      :auth_config_plaintext,
      :mount_path,
      :base_path,
      :namespace
    ])
    |> validate_inclusion(:auth_method, @auth_methods)
    |> encrypt_auth_config()
  end

  def status_changeset(config, attrs) do
    config
    |> cast(attrs, [:last_connected_at, :connection_status])
  end

  defp encrypt_auth_config(changeset) do
    case get_change(changeset, :auth_config_plaintext) do
      nil ->
        changeset

      plaintext when is_map(plaintext) ->
        json = Jason.encode!(plaintext)
        encrypted = SecretCrypto.encrypt(json)
        put_change(changeset, :auth_config, encrypted)
    end
  end

  @doc """
  Decrypts the auth_config binary, returning the plaintext map.
  """
  def decrypt_auth_config(nil), do: {:ok, %{}}

  def decrypt_auth_config(encrypted) when is_binary(encrypted) do
    case SecretCrypto.decrypt(encrypted) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end
end
