defmodule ZentinelCp.Auth.SamlProvider do
  @moduledoc """
  Schema for SAML 2.0 Identity Provider configurations.
  Supports SP-initiated SSO with configurable group mapping.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(admin operator reader)

  schema "saml_providers" do
    field :name, :string
    field :entity_id, :string
    field :sso_url, :string
    field :certificate, :string
    field :sign_requests, :boolean, default: false
    field :default_role, :string, default: "reader"
    field :auto_provision, :boolean, default: true
    field :group_mapping, :map, default: %{}
    field :enabled, :boolean, default: true
    field :fallback_to_password, :boolean, default: true

    belongs_to :org, ZentinelCp.Orgs.Org

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :org_id,
      :name,
      :entity_id,
      :sso_url,
      :certificate,
      :sign_requests,
      :default_role,
      :auto_provision,
      :group_mapping,
      :enabled,
      :fallback_to_password
    ])
    |> validate_required([:org_id, :name, :entity_id, :sso_url, :certificate])
    |> validate_inclusion(:default_role, @roles)
    |> validate_format(:sso_url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint([:org_id, :entity_id])
    |> foreign_key_constraint(:org_id)
  end
end
