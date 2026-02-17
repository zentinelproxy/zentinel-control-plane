defmodule ZentinelCp.Policies.Evaluator do
  @moduledoc """
  Evaluates policy expressions against a context map.

  ## Supported Operations
  - `field == value` — equality
  - `field != value` — inequality
  - `field > value` — greater than (numeric)
  - `field < value` — less than (numeric)
  - `field >= value` — greater than or equal (numeric)
  - `field <= value` — less than or equal (numeric)
  - `field in [val1, val2]` — inclusion in list
  - `field not_in [val1, val2]` — exclusion from list
  - `field contains substring` — string contains
  """

  @doc """
  Evaluates an expression string against a context map.
  Returns `{:ok, true}` if the policy passes, `{:ok, false}` if it fails,
  or `{:error, reason}` on parse error.
  """
  def evaluate(expression, context) when is_binary(expression) and is_map(context) do
    expression = String.trim(expression)

    cond do
      String.contains?(expression, " && ") ->
        parts = String.split(expression, " && ")
        results = Enum.map(parts, &evaluate(&1, context))
        all_pass = Enum.all?(results, &(&1 == {:ok, true}))

        error =
          Enum.find(results, fn
            {:error, _} -> true
            _ -> false
          end)

        if error, do: error, else: {:ok, all_pass}

      String.contains?(expression, " || ") ->
        parts = String.split(expression, " || ")
        results = Enum.map(parts, &evaluate(&1, context))
        any_pass = Enum.any?(results, &(&1 == {:ok, true}))

        error =
          Enum.find(results, fn
            {:error, _} -> true
            _ -> false
          end)

        if error, do: error, else: {:ok, any_pass}

      true ->
        evaluate_single(expression, context)
    end
  end

  def evaluate(_, _), do: {:error, "invalid expression"}

  defp evaluate_single(expression, context) do
    cond do
      match = Regex.run(~r/^(\w+)\s+not_in\s+\[(.+)\]$/, expression) ->
        [_, field, values_str] = match
        values = parse_list_values(values_str)
        field_value = get_context_value(context, field)
        {:ok, field_value not in values}

      match = Regex.run(~r/^(\w+)\s+in\s+\[(.+)\]$/, expression) ->
        [_, field, values_str] = match
        values = parse_list_values(values_str)
        field_value = get_context_value(context, field)
        {:ok, field_value in values}

      match = Regex.run(~r/^(\w+)\s+contains\s+\"(.+)\"$/, expression) ->
        [_, field, substring] = match
        field_value = get_context_value(context, field) |> to_string()
        {:ok, String.contains?(field_value, substring)}

      match = Regex.run(~r/^(\w+)\s*>=\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        compare_values(context, field, value_str, &>=/2)

      match = Regex.run(~r/^(\w+)\s*<=\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        compare_values(context, field, value_str, &<=/2)

      match = Regex.run(~r/^(\w+)\s*!=\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        field_value = get_context_value(context, field)
        parsed_value = parse_value(String.trim(value_str))
        {:ok, field_value != parsed_value}

      match = Regex.run(~r/^(\w+)\s*==\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        field_value = get_context_value(context, field)
        parsed_value = parse_value(String.trim(value_str))
        {:ok, field_value == parsed_value}

      match = Regex.run(~r/^(\w+)\s*>\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        compare_values(context, field, value_str, &>/2)

      match = Regex.run(~r/^(\w+)\s*<\s*(.+)$/, expression) ->
        [_, field, value_str] = match
        compare_values(context, field, value_str, &</2)

      true ->
        {:error, "unrecognized expression: #{expression}"}
    end
  end

  defp compare_values(context, field, value_str, comparator) do
    field_value = get_context_value(context, field)
    parsed_value = parse_value(String.trim(value_str))

    case {field_value, parsed_value} do
      {a, b} when is_number(a) and is_number(b) ->
        {:ok, comparator.(a, b)}

      _ ->
        {:ok, comparator.(to_string(field_value), to_string(parsed_value))}
    end
  end

  defp get_context_value(context, field) do
    Map.get(context, field) || Map.get(context, String.to_atom(field))
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value("nil"), do: nil
  defp parse_value("null"), do: nil

  defp parse_value(str) do
    str = String.trim(str)

    cond do
      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") ->
        String.slice(str, 1..-2//1)

      String.contains?(str, ".") ->
        case Float.parse(str) do
          {f, ""} -> f
          _ -> str
        end

      true ->
        case Integer.parse(str) do
          {i, ""} -> i
          _ -> str
        end
    end
  end

  defp parse_list_values(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_value/1)
  end
end
