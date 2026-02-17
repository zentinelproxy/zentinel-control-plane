defmodule ZentinelCp.Bundles.ConfigValidationRule do
  @moduledoc """
  Schema for config validation rules.

  Rules are applied to bundle configurations before rollouts to ensure
  they meet project-specific requirements.

  ## Rule Types

  - `required_field`: Ensures a field exists in the config
  - `forbidden_pattern`: Rejects configs containing a regex pattern
  - `allowed_pattern`: Requires configs to match a regex pattern
  - `max_size`: Limits the config size in bytes
  - `json_schema`: Validates against a JSON schema (stored in config)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rule_types ~w(required_field forbidden_pattern allowed_pattern max_size json_schema)
  @severities ~w(error warning info)

  schema "config_validation_rules" do
    field :name, :string
    field :description, :string
    field :rule_type, :string
    field :pattern, :string
    field :config, :map, default: %{}
    field :severity, :string, default: "error"
    field :enabled, :boolean, default: true

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid rule types.
  """
  def rule_types, do: @rule_types

  @doc """
  Returns the list of valid severities.
  """
  def severities, do: @severities

  @doc """
  Changeset for creating a validation rule.
  """
  def create_changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :name,
      :description,
      :rule_type,
      :pattern,
      :config,
      :severity,
      :enabled,
      :project_id
    ])
    |> validate_required([:name, :rule_type, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:rule_type, @rule_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_rule_config()
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a validation rule.
  """
  def update_changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :description, :rule_type, :pattern, :config, :severity, :enabled])
    |> validate_required([:name, :rule_type])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:rule_type, @rule_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_rule_config()
  end

  defp validate_rule_config(changeset) do
    rule_type = get_field(changeset, :rule_type)
    pattern = get_field(changeset, :pattern)

    case rule_type do
      type when type in ["forbidden_pattern", "allowed_pattern"] ->
        if pattern do
          validate_regex_pattern(changeset)
        else
          add_error(changeset, :pattern, "is required for #{rule_type} rules")
        end

      "required_field" ->
        if pattern do
          changeset
        else
          add_error(changeset, :pattern, "field name is required")
        end

      "max_size" ->
        config = get_field(changeset, :config) || %{}

        if Map.has_key?(config, "max_bytes") do
          changeset
        else
          add_error(changeset, :config, "max_bytes is required in config")
        end

      "json_schema" ->
        config = get_field(changeset, :config) || %{}

        if Map.has_key?(config, "schema") do
          changeset
        else
          add_error(changeset, :config, "schema is required in config")
        end

      _ ->
        changeset
    end
  end

  defp validate_regex_pattern(changeset) do
    validate_change(changeset, :pattern, fn _, pattern ->
      case Regex.compile(pattern) do
        {:ok, _} -> []
        {:error, _} -> [pattern: "is not a valid regular expression"]
      end
    end)
  end
end
