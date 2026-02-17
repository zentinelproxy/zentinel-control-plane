defmodule ZentinelCp.Webhooks.AdaptersTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Webhooks.{GitLabAdapter, BitbucketAdapter, GiteaAdapter, GenericAdapter}

  describe "GitLabAdapter" do
    test "verifies valid token" do
      assert GitLabAdapter.verify_signature("payload", "my-secret", "my-secret")
    end

    test "rejects invalid token" do
      refute GitLabAdapter.verify_signature("payload", "wrong", "my-secret")
    end

    test "parses push event" do
      payload = %{
        "ref" => "refs/heads/main",
        "checkout_sha" => "abc123",
        "project" => %{"path_with_namespace" => "org/repo"},
        "commits" => [
          %{
            "id" => "abc123",
            "added" => ["file1.kdl"],
            "modified" => ["file2.kdl"],
            "removed" => []
          }
        ]
      }

      result = GitLabAdapter.parse_push_event(payload)
      assert result.repo == "org/repo"
      assert result.branch == "main"
      assert result.commit == "abc123"
      assert result.event_type == :push
      assert "file1.kdl" in result.commits
      assert "file2.kdl" in result.commits
    end

    test "parses tag push event" do
      payload = %{
        "ref" => "refs/tags/v1.0.0",
        "checkout_sha" => "def456",
        "project" => %{"path_with_namespace" => "org/repo"},
        "commits" => []
      }

      result = GitLabAdapter.parse_push_event(payload)
      assert result.tag == "v1.0.0"
      assert result.event_type == :tag_push
      assert result.branch == nil
    end
  end

  describe "BitbucketAdapter" do
    test "verifies valid HMAC signature" do
      secret = "test-secret"
      payload = "test-payload"

      signature =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      assert BitbucketAdapter.verify_signature(payload, signature, secret)
    end

    test "rejects invalid signature" do
      refute BitbucketAdapter.verify_signature("payload", "wrong", "secret")
    end

    test "parses push event" do
      payload = %{
        "repository" => %{"full_name" => "org/repo"},
        "push" => %{
          "changes" => [
            %{
              "new" => %{
                "type" => "branch",
                "name" => "main",
                "target" => %{"hash" => "abc123"}
              }
            }
          ]
        }
      }

      result = BitbucketAdapter.parse_push_event(payload)
      assert result.repo == "org/repo"
      assert result.branch == "main"
      assert result.commit == "abc123"
    end
  end

  describe "GiteaAdapter" do
    test "verifies valid HMAC signature" do
      secret = "test-secret"
      payload = "test-payload"

      signature =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      assert GiteaAdapter.verify_signature(payload, signature, secret)
    end

    test "parses push event (GitHub-compatible format)" do
      payload = %{
        "ref" => "refs/heads/main",
        "after" => "abc123",
        "repository" => %{"full_name" => "org/repo"},
        "commits" => [
          %{"added" => ["zentinel.kdl"], "modified" => [], "removed" => []}
        ]
      }

      result = GiteaAdapter.parse_push_event(payload)
      assert result.repo == "org/repo"
      assert result.branch == "main"
      assert result.commit == "abc123"
      assert "zentinel.kdl" in result.commits
    end
  end

  describe "GenericAdapter" do
    test "verifies HMAC signature" do
      secret = "test-secret"
      payload = "test-payload"

      signature =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      assert GenericAdapter.verify_signature(payload, signature, secret)
    end

    test "parses minimal push event" do
      payload = %{
        "ref" => "refs/heads/main",
        "repository" => "org/repo",
        "commit" => "abc123"
      }

      result = GenericAdapter.parse_push_event(payload)
      assert result.repo == "org/repo"
      assert result.branch == "main"
      assert result.commit == "abc123"
    end
  end
end
