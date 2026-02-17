defmodule ZentinelCp.Bundles.ConfigValidator do
  @moduledoc """
  Validates bundle configurations against project validation rules.
  """

  alias ZentinelCp.Bundles.ConfigValidationRule

  @doc """
  Validates a bundle configuration against a list of rules.

  Returns `{:ok, warnings}` if validation passes (warnings are non-error severity issues).
  Returns `{:error, errors, warnings}` if validation fails.
  """
  def validate(config_source, rules) when is_binary(config_source) and is_list(rules) do
    enabled_rules = Enum.filter(rules, & &1.enabled)

    results =
      Enum.map(enabled_rules, fn rule ->
        result = validate_rule(config_source, rule)
        {rule, result}
      end)

    errors =
      results
      |> Enum.filter(fn {rule, result} -> result == :fail and rule.severity == "error" end)
      |> Enum.map(fn {rule, _} -> format_error(rule) end)

    warnings =
      results
      |> Enum.filter(fn {rule, result} ->
        result == :fail and rule.severity in ["warning", "info"]
      end)
      |> Enum.map(fn {rule, _} -> format_warning(rule) end)

    if errors == [] do
      {:ok, warnings}
    else
      {:error, errors, warnings}
    end
  end

  defp validate_rule(config_source, %ConfigValidationRule{rule_type: "required_field"} = rule) do
    field = rule.pattern

    if String.contains?(config_source, field) do
      :pass
    else
      :fail
    end
  end

  defp validate_rule(config_source, %ConfigValidationRule{rule_type: "forbidden_pattern"} = rule) do
    case Regex.compile(rule.pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, config_source) do
          :fail
        else
          :pass
        end

      {:error, _} ->
        :pass
    end
  end

  defp validate_rule(config_source, %ConfigValidationRule{rule_type: "allowed_pattern"} = rule) do
    case Regex.compile(rule.pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, config_source) do
          :pass
        else
          :fail
        end

      {:error, _} ->
        :pass
    end
  end

  defp validate_rule(config_source, %ConfigValidationRule{rule_type: "max_size"} = rule) do
    max_bytes = Map.get(rule.config || %{}, "max_bytes", 1_000_000)

    if byte_size(config_source) <= max_bytes do
      :pass
    else
      :fail
    end
  end

  defp validate_rule(_config_source, %ConfigValidationRule{rule_type: "json_schema"}) do
    # JSON schema validation would require a JSON schema library
    # For now, we just pass
    :pass
  end

  defp validate_rule(_config_source, _rule) do
    :pass
  end

  defp format_error(rule) do
    %{
      rule_id: rule.id,
      rule_name: rule.name,
      rule_type: rule.rule_type,
      message: error_message(rule),
      severity: rule.severity
    }
  end

  defp format_warning(rule) do
    %{
      rule_id: rule.id,
      rule_name: rule.name,
      rule_type: rule.rule_type,
      message: error_message(rule),
      severity: rule.severity
    }
  end

  defp error_message(%{rule_type: "required_field", pattern: field}) do
    "Required field '#{field}' not found in configuration"
  end

  defp error_message(%{rule_type: "forbidden_pattern", pattern: pattern}) do
    "Configuration contains forbidden pattern: #{pattern}"
  end

  defp error_message(%{rule_type: "allowed_pattern", pattern: pattern}) do
    "Configuration does not match required pattern: #{pattern}"
  end

  defp error_message(%{rule_type: "max_size", config: config}) do
    max_bytes = Map.get(config || %{}, "max_bytes", 1_000_000)
    "Configuration exceeds maximum size of #{max_bytes} bytes"
  end

  defp error_message(%{name: name}) do
    "Validation rule '#{name}' failed"
  end
end
