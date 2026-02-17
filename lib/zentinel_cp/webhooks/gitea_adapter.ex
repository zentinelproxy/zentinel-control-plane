defmodule ZentinelCp.Webhooks.GiteaAdapter do
  @moduledoc """
  Gitea/Forgejo webhook adapter.
  Verifies HMAC-SHA256 signatures and parses push event format.
  """

  @doc """
  Verifies a Gitea webhook HMAC-SHA256 signature.
  """
  def verify_signature(payload, signature, secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, signature || "")
  end

  @doc """
  Parses a Gitea push event into a normalized format.
  Same format as GitHub push events (Gitea is API-compatible).
  """
  def parse_push_event(payload) do
    %{
      repo: get_in(payload, ["repository", "full_name"]),
      branch: extract_branch(payload["ref"]),
      commit: payload["after"],
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
