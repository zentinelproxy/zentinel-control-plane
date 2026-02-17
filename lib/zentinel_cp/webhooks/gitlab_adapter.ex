defmodule ZentinelCp.Webhooks.GitLabAdapter do
  @moduledoc """
  GitLab webhook adapter.
  Verifies X-Gitlab-Token and parses push event format.
  """

  @doc """
  Verifies a GitLab webhook using the secret token header.
  GitLab sends the secret as X-Gitlab-Token (plain comparison).
  """
  def verify_signature(_payload, token, secret) do
    Plug.Crypto.secure_compare(token || "", secret || "")
  end

  @doc """
  Parses a GitLab push event into a normalized format.
  """
  def parse_push_event(payload) do
    %{
      repo: payload["project"]["path_with_namespace"],
      branch: extract_branch(payload["ref"]),
      commit: payload["checkout_sha"] || get_in(payload, ["commits", Access.at(0), "id"]),
      commits: normalize_commits(payload["commits"] || []),
      ref: payload["ref"],
      tag: extract_tag(payload["ref"]),
      event_type: event_type(payload["ref"])
    }
  end

  defp extract_branch("refs/heads/" <> branch), do: branch
  defp extract_branch(_), do: nil

  defp extract_tag("refs/tags/" <> tag), do: tag
  defp extract_tag(_), do: nil

  defp event_type("refs/tags/" <> _), do: :tag_push
  defp event_type("refs/heads/" <> _), do: :push
  defp event_type(_), do: :unknown

  defp normalize_commits(commits) do
    Enum.flat_map(commits, fn commit ->
      (commit["added"] || []) ++ (commit["modified"] || []) ++ (commit["removed"] || [])
    end)
    |> Enum.uniq()
  end
end
