defmodule ZentinelCp.Bundles.Diff do
  @moduledoc """
  Computes diffs between two bundle configurations.

  Uses `List.myers_difference/2` from stdlib for line-level diffing.
  """

  @doc """
  Computes a config diff between two bundles.

  Returns a list of `{:eq, lines}`, `{:ins, lines}`, `{:del, lines}` tuples.
  """
  def config_diff(bundle_a, bundle_b) do
    lines_a = split_lines(bundle_a.config_source || "")
    lines_b = split_lines(bundle_b.config_source || "")

    List.myers_difference(lines_a, lines_b)
  end

  @doc """
  Computes a manifest diff between two bundles.

  Returns `%{added: [...], removed: [...], modified: [...], unchanged: [...]}`.
  """
  def manifest_diff(bundle_a, bundle_b) do
    files_a = extract_manifest_files(bundle_a.manifest)
    files_b = extract_manifest_files(bundle_b.manifest)

    keys_a = MapSet.new(Map.keys(files_a))
    keys_b = MapSet.new(Map.keys(files_b))

    added = MapSet.difference(keys_b, keys_a) |> MapSet.to_list()
    removed = MapSet.difference(keys_a, keys_b) |> MapSet.to_list()
    common = MapSet.intersection(keys_a, keys_b) |> MapSet.to_list()

    {modified, unchanged} =
      Enum.split_with(common, fn key ->
        Map.get(files_a, key) != Map.get(files_b, key)
      end)

    %{
      added: Enum.sort(added),
      removed: Enum.sort(removed),
      modified: Enum.sort(modified),
      unchanged: Enum.sort(unchanged)
    }
  end

  @doc """
  Renders a diff as annotated lines for display.

  Returns a list of `%{type: :eq | :ins | :del, line: string, number_a: int | nil, number_b: int | nil}`.
  """
  def annotate_diff(diff) do
    {lines, _num_a, _num_b} =
      Enum.reduce(diff, {[], 1, 1}, fn
        {:eq, content}, {acc, num_a, num_b} ->
          annotated =
            Enum.with_index(content)
            |> Enum.map(fn {line, i} ->
              %{type: :eq, line: line, number_a: num_a + i, number_b: num_b + i}
            end)

          {acc ++ annotated, num_a + length(content), num_b + length(content)}

        {:ins, content}, {acc, num_a, num_b} ->
          annotated =
            Enum.with_index(content)
            |> Enum.map(fn {line, i} ->
              %{type: :ins, line: line, number_a: nil, number_b: num_b + i}
            end)

          {acc ++ annotated, num_a, num_b + length(content)}

        {:del, content}, {acc, num_a, num_b} ->
          annotated =
            Enum.with_index(content)
            |> Enum.map(fn {line, i} ->
              %{type: :del, line: line, number_a: num_a + i, number_b: nil}
            end)

          {acc ++ annotated, num_a + length(content), num_b}
      end)

    lines
  end

  @doc """
  Returns summary stats for a diff.
  """
  def diff_stats(diff) do
    Enum.reduce(diff, %{additions: 0, deletions: 0, unchanged: 0}, fn
      {:eq, lines}, acc -> %{acc | unchanged: acc.unchanged + length(lines)}
      {:ins, lines}, acc -> %{acc | additions: acc.additions + length(lines)}
      {:del, lines}, acc -> %{acc | deletions: acc.deletions + length(lines)}
    end)
  end

  @doc """
  Extracts semantic information from a config diff.

  Parses KDL lines to identify which services were added, removed, or modified,
  and whether settings changed.

  Returns `%{services_added: [...], services_removed: [...], services_modified: [...], settings_changed: bool}`.
  """
  def semantic_diff(bundle_a, bundle_b) do
    routes_a = extract_route_names(bundle_a.config_source || "")
    routes_b = extract_route_names(bundle_b.config_source || "")

    set_a = MapSet.new(routes_a)
    set_b = MapSet.new(routes_b)

    added = MapSet.difference(set_b, set_a) |> MapSet.to_list() |> Enum.sort()
    removed = MapSet.difference(set_a, set_b) |> MapSet.to_list() |> Enum.sort()
    common = MapSet.intersection(set_a, set_b) |> MapSet.to_list()

    # For modified: check if the config between this route's block changed
    config_diff_result = config_diff(bundle_a, bundle_b)
    has_changes = Enum.any?(config_diff_result, fn {type, _} -> type != :eq end)

    modified =
      if has_changes do
        # Consider common routes as potentially modified if the overall config changed
        common |> Enum.sort()
      else
        []
      end

    settings_a = extract_settings_block(bundle_a.config_source || "")
    settings_b = extract_settings_block(bundle_b.config_source || "")

    %{
      services_added: added,
      services_removed: removed,
      services_modified: modified,
      settings_changed: settings_a != settings_b
    }
  end

  @doc """
  Transforms annotated diff lines into side-by-side paired lines.

  Returns a list of `%{left: line_map | nil, right: line_map | nil}` pairs.
  """
  def side_by_side_diff(annotated_lines) do
    {pairs, pending_dels} =
      Enum.reduce(annotated_lines, {[], []}, fn line, {pairs, dels} ->
        case line.type do
          :eq ->
            # Flush any pending deletions as left-only
            flushed = Enum.map(dels, fn d -> %{left: d, right: nil} end)
            {pairs ++ flushed ++ [%{left: line, right: line}], []}

          :del ->
            {pairs, dels ++ [line]}

          :ins ->
            case dels do
              [del | rest] ->
                # Pair this insertion with a pending deletion
                {pairs ++ [%{left: del, right: line}], rest}

              [] ->
                {pairs ++ [%{left: nil, right: line}], []}
            end
        end
      end)

    # Flush remaining deletions
    remaining = Enum.map(pending_dels, fn d -> %{left: d, right: nil} end)
    pairs ++ remaining
  end

  defp extract_route_names(config_source) do
    Regex.scan(~r/route\s+"([^"]+)"/, config_source)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_settings_block(config_source) do
    case Regex.run(~r/settings \{[^}]*\}/s, config_source) do
      [block] -> block
      _ -> ""
    end
  end

  defp split_lines(text) do
    String.split(text, "\n")
  end

  defp extract_manifest_files(nil), do: %{}

  defp extract_manifest_files(manifest) when is_map(manifest) do
    case Map.get(manifest, "files") do
      files when is_map(files) -> files
      _ -> %{}
    end
  end
end
