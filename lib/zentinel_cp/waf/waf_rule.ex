defmodule ZentinelCp.Waf.WafRule do
  @moduledoc """
  Schema for WAF rules — the catalog of detection rules (built-in + custom).

  Each rule has a unique `rule_id` (e.g., "CRS-942100") and belongs to a category.
  Rules don't contain regex patterns; the proxy handles detection.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(sqli xss lfi rfi rce scanner protocol data_leak custom)
  @severities ~w(low medium high critical)
  @actions ~w(block log disable)
  @phases ~w(request response)

  schema "waf_rules" do
    field :rule_id, :string
    field :name, :string
    field :description, :string
    field :category, :string
    field :severity, :string, default: "medium"
    field :default_action, :string, default: "block"
    field :targets, {:array, :string}, default: []
    field :tags, {:array, :string}, default: []
    field :is_builtin, :boolean, default: true
    field :phase, :string, default: "request"

    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories
  def severities, do: @severities

  def create_changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :rule_id,
      :name,
      :description,
      :category,
      :severity,
      :default_action,
      :targets,
      :tags,
      :is_builtin,
      :phase
    ])
    |> validate_required([:rule_id, :name, :category])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:default_action, @actions)
    |> validate_inclusion(:phase, @phases)
    |> unique_constraint(:rule_id)
  end
end
