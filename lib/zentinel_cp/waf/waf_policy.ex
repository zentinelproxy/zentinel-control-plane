defmodule ZentinelCp.Waf.WafPolicy do
  @moduledoc """
  Schema for WAF policies — project-scoped policy configurations.

  A policy defines the WAF mode, sensitivity level, enabled categories,
  and optional size limits. Services bind to a policy via `waf_policy_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @modes ~w(block detect_only challenge)
  @sensitivities ~w(low medium high paranoid)
  @actions ~w(block log disable)

  schema "waf_policies" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :enabled, :boolean, default: true
    field :mode, :string, default: "block"
    field :sensitivity, :string, default: "medium"
    field :enabled_categories, {:array, :string}, default: []
    field :default_action, :string, default: "block"
    field :max_body_size, :integer
    field :max_header_size, :integer
    field :max_uri_length, :integer
    field :allowed_content_types, {:array, :string}, default: []

    belongs_to :project, ZentinelCp.Projects.Project
    has_many :rule_overrides, ZentinelCp.Waf.WafPolicyRuleOverride
    has_many :services, ZentinelCp.Services.Service

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes
  def sensitivities, do: @sensitivities

  def create_changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :mode,
      :sensitivity,
      :enabled_categories,
      :default_action,
      :max_body_size,
      :max_header_size,
      :max_uri_length,
      :allowed_content_types,
      :project_id
    ])
    |> validate_required([:name, :mode, :sensitivity, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_inclusion(:default_action, @actions)
    |> validate_categories()
    |> validate_number(:max_body_size, greater_than: 0)
    |> validate_number(:max_header_size, greater_than: 0)
    |> validate_number(:max_uri_length, greater_than: 0)
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :mode,
      :sensitivity,
      :enabled_categories,
      :default_action,
      :max_body_size,
      :max_header_size,
      :max_uri_length,
      :allowed_content_types
    ])
    |> validate_required([:name, :mode, :sensitivity])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_inclusion(:default_action, @actions)
    |> validate_categories()
    |> validate_number(:max_body_size, greater_than: 0)
    |> validate_number(:max_header_size, greater_than: 0)
    |> validate_number(:max_uri_length, greater_than: 0)
  end

  defp validate_categories(changeset) do
    alias ZentinelCp.Waf.WafRule
    valid = WafRule.categories()

    case get_field(changeset, :enabled_categories) do
      nil ->
        changeset

      cats ->
        if Enum.all?(cats, &(&1 in valid)) do
          changeset
        else
          add_error(changeset, :enabled_categories, "contains invalid categories")
        end
    end
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 50)
  end
end
