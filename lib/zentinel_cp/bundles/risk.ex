defmodule ZentinelCp.Bundles.Risk do
  @moduledoc """
  Automatic risk scoring for bundle changes.

  Compares the new bundle's config against the previous bundle to assess
  the risk level of a deployment. Used during compilation to set the
  bundle's `risk_level` field.
  """

  @doc """
  Scores the risk of a bundle based on its config and the previous bundle's config.

  Returns `{level, reasons}` where level is `"low"`, `"medium"`, or `"high"`
  and reasons is a list of strings explaining the risk factors.
  """
  @spec score(String.t(), String.t() | nil) :: {String.t(), [String.t()]}
  def score(new_config, prev_config) do
    reasons =
      []
      |> check_auth_policy_changed(new_config, prev_config)
      |> check_tls_changed(new_config, prev_config)
      |> check_many_route_changes(new_config, prev_config)
      |> check_upstream_removed(new_config, prev_config)
      |> check_rate_limit_changed(new_config, prev_config)

    level =
      cond do
        Enum.any?(reasons, &high_risk?/1) -> "high"
        length(reasons) > 0 -> "medium"
        true -> "low"
      end

    {level, reasons}
  end

  @doc """
  Scores a bundle against the previous compiled bundle in the same project.
  Returns `{level, reasons}`.
  """
  @spec score_against_previous(String.t(), String.t()) :: {String.t(), [String.t()]}
  def score_against_previous(new_config, project_id) do
    prev_config =
      case ZentinelCp.Bundles.get_latest_bundle(project_id) do
        %{config_source: source} when is_binary(source) -> source
        _ -> nil
      end

    score(new_config, prev_config)
  end

  ## Risk checks

  defp check_auth_policy_changed(reasons, new_config, prev_config) do
    new_auth = extract_blocks(new_config, ~r/(?:auth|authentication|authorization)\s*\{[^}]*\}/s)

    prev_auth =
      extract_blocks(prev_config, ~r/(?:auth|authentication|authorization)\s*\{[^}]*\}/s)

    if new_auth != prev_auth and prev_auth != [] do
      ["auth_policy_changed" | reasons]
    else
      reasons
    end
  end

  defp check_tls_changed(reasons, new_config, prev_config) do
    new_tls = extract_blocks(new_config, ~r/tls\s*\{[^}]*\}/s)
    prev_tls = extract_blocks(prev_config, ~r/tls\s*\{[^}]*\}/s)

    if new_tls != prev_tls and prev_tls != [] do
      ["tls_config_changed" | reasons]
    else
      reasons
    end
  end

  defp check_many_route_changes(reasons, new_config, prev_config) do
    new_count = count_pattern(new_config, ~r/route\s/)
    prev_count = count_pattern(prev_config, ~r/route\s/)
    delta = abs(new_count - prev_count)

    if delta > 10 do
      ["many_route_changes" | reasons]
    else
      reasons
    end
  end

  defp check_upstream_removed(reasons, new_config, prev_config) do
    new_upstreams = extract_names(new_config, ~r/upstream\s+"([^"]+)"/)
    prev_upstreams = extract_names(prev_config, ~r/upstream\s+"([^"]+)"/)
    removed = prev_upstreams -- new_upstreams

    if removed != [] do
      ["upstream_removed" | reasons]
    else
      reasons
    end
  end

  defp check_rate_limit_changed(reasons, new_config, prev_config) do
    new_rl = extract_blocks(new_config, ~r/rate_limit\s*\{[^}]*\}/s)
    prev_rl = extract_blocks(prev_config, ~r/rate_limit\s*\{[^}]*\}/s)

    if new_rl != prev_rl and prev_rl != [] do
      ["rate_limit_changed" | reasons]
    else
      reasons
    end
  end

  ## Helpers

  defp high_risk?(reason), do: reason in ~w(auth_policy_changed tls_config_changed)

  defp extract_blocks(nil, _regex), do: []

  defp extract_blocks(config, regex) do
    Regex.scan(regex, config)
    |> Enum.map(fn [match | _] -> String.trim(match) end)
    |> Enum.sort()
  end

  defp count_pattern(nil, _regex), do: 0

  defp count_pattern(config, regex) do
    Regex.scan(regex, config) |> length()
  end

  defp extract_names(nil, _regex), do: []

  defp extract_names(config, regex) do
    Regex.scan(regex, config)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.sort()
  end
end
