defmodule ZentinelCp.Webhooks.BitbucketAdapter do
  @moduledoc """
  Bitbucket webhook adapter.
  Verifies HMAC-SHA256 signatures and parses push event format.
  """

  @doc """
  Verifies a Bitbucket webhook HMAC-SHA256 signature.
  """
  def verify_signature(payload, signature, secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, signature || "")
  end

  @doc """
  Parses a Bitbucket push event into a normalized format.
  """
  def parse_push_event(payload) do
    changes = get_in(payload, ["push", "changes"]) || []
    change = List.first(changes) || %{}
    new_ref = change["new"] || %{}

    %{
      repo: get_in(payload, ["repository", "full_name"]),
      branch: if(new_ref["type"] == "branch", do: new_ref["name"]),
      commit: get_in(new_ref, ["target", "hash"]),
      commits: [],
      ref: new_ref["name"],
      tag: if(new_ref["type"] == "tag", do: new_ref["name"]),
      event_type: if(new_ref["type"] == "tag", do: :tag_push, else: :push)
    }
  end
end
