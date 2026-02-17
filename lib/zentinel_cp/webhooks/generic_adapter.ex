defmodule ZentinelCp.Webhooks.GenericAdapter do
  @moduledoc """
  Generic webhook adapter with configurable HMAC header name and secret.
  """

  @doc """
  Verifies a generic webhook HMAC signature using a configurable header.
  """
  def verify_signature(payload, signature, secret, algorithm \\ :sha256) do
    expected =
      :crypto.mac(:hmac, algorithm, secret, payload)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, signature || "")
  end

  @doc """
  Parses a generic webhook trigger into a normalized format.
  Expects a minimal payload with `ref`, `repository`, and `commit` fields.
  """
  def parse_push_event(payload) do
    %{
      repo: payload["repository"] || payload["repo"],
      branch: extract_branch(payload["ref"]),
      commit: payload["commit"] || payload["sha"],
      commits: [],
      ref: payload["ref"],
      tag: extract_tag(payload["ref"]),
      event_type: event_type(payload["ref"])
    }
  end

  defp extract_branch("refs/heads/" <> branch), do: branch
  defp extract_branch(ref) when is_binary(ref), do: ref
  defp extract_branch(_), do: nil

  defp extract_tag("refs/tags/" <> tag), do: tag
  defp extract_tag(_), do: nil

  defp event_type("refs/tags/" <> _), do: :tag_push
  defp event_type(_), do: :push
end
