defmodule ZentinelCp.Auth.OidcProvider do
  @moduledoc """
  Schema for OIDC Identity Provider configurations.
  Each org can have multiple OIDC providers (Okta, Azure AD, Google Workspace, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(admin operator reader)

  schema "oidc_providers" do
    field :name, :string
    field :issuer, :string
    field :client_id, :string
    field :client_secret_encrypted, :binary
    field :discovery_url, :string
    field :scopes, {:array, :string}, default: ["openid", "email", "profile"]
    field :default_role, :string, default: "reader"
    field :auto_provision, :boolean, default: true
    field :group_mapping, :map, default: %{}
    field :enabled, :boolean, default: true
    field :fallback_to_password, :boolean, default: true

    # Virtual field for setting the secret
    field :client_secret, :string, virtual: true, redact: true

    belongs_to :org, ZentinelCp.Orgs.Org

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :org_id,
      :name,
      :issuer,
      :client_id,
      :client_secret,
      :discovery_url,
      :scopes,
      :default_role,
      :auto_provision,
      :group_mapping,
      :enabled,
      :fallback_to_password
    ])
    |> validate_required([:org_id, :name, :issuer, :client_id, :discovery_url])
    |> validate_inclusion(:default_role, @roles)
    |> validate_format(:discovery_url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> encrypt_client_secret()
    |> unique_constraint([:org_id, :issuer])
    |> foreign_key_constraint(:org_id)
  end

  defp encrypt_client_secret(changeset) do
    case get_change(changeset, :client_secret) do
      nil ->
        # Require on create
        if changeset.data.id do
          changeset
        else
          validate_required(changeset, [:client_secret])
        end

      secret when is_binary(secret) ->
        encrypted = ZentinelCp.Auth.Encryption.encrypt(secret)
        put_change(changeset, :client_secret_encrypted, encrypted)

      _ ->
        changeset
    end
  end

  def decrypt_client_secret(%__MODULE__{client_secret_encrypted: encrypted})
      when is_binary(encrypted) do
    ZentinelCp.Auth.Encryption.decrypt(encrypted)
  end

  def decrypt_client_secret(_), do: nil
end
