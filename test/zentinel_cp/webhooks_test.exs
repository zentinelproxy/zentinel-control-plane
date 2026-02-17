defmodule ZentinelCp.WebhooksTest do
  use ZentinelCp.DataCase

  import Mox

  alias ZentinelCp.Webhooks

  setup :verify_on_exit!

  describe "verify_signature/2" do
    test "returns true for valid signature" do
      secret = Application.get_env(:zentinel_cp, :github_webhook)[:secret]
      payload = ~s({"action":"push"})

      mac =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      signature = "sha256=" <> mac

      assert Webhooks.verify_signature(payload, signature)
    end

    test "returns false for invalid signature" do
      payload = ~s({"action":"push"})
      refute Webhooks.verify_signature(payload, "sha256=invalid")
    end

    test "returns false for nil payload" do
      refute Webhooks.verify_signature(nil, "sha256=abc")
    end

    test "returns false for nil signature" do
      refute Webhooks.verify_signature("body", nil)
    end
  end

  describe "process_github_push/1" do
    test "creates bundle when project matches and config file changed" do
      project =
        ZentinelCp.ProjectsFixtures.project_fixture(%{
          github_repo: "raskell-io/test-config",
          github_branch: "main",
          config_path: "zentinel.kdl"
        })

      config_content = """
      system {
        workers 4
      }
      """

      expect(ZentinelCp.Webhooks.GitHubClient.Mock, :fetch_file, fn
        "raskell-io/test-config", "abc123def456abc123def456abc123def456abc1", "zentinel.kdl" ->
          config_content
      end)

      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "raskell-io/test-config"},
        "head_commit" => %{
          "id" => "abc123def456abc123def456abc123def456abc1",
          "message" => "Update config"
        },
        "commits" => [
          %{
            "added" => [],
            "modified" => ["zentinel.kdl"],
            "removed" => []
          }
        ]
      }

      assert {:ok, bundle} = Webhooks.process_github_push(payload)
      assert bundle.source_type == "git"
      assert bundle.source_ref == "abc123def456abc123def456abc123def456abc1"
      assert bundle.source_branch == "main"
      assert bundle.source_repo == "raskell-io/test-config"
      assert bundle.project_id == project.id
      assert String.starts_with?(bundle.version, "git-")
    end

    test "ignores push to non-matching branch" do
      _project =
        ZentinelCp.ProjectsFixtures.project_fixture(%{
          github_repo: "raskell-io/test-config",
          github_branch: "main"
        })

      payload = %{
        "ref" => "refs/heads/develop",
        "repository" => %{"full_name" => "raskell-io/test-config"},
        "head_commit" => %{"id" => "abc123", "message" => "dev change"},
        "commits" => [%{"added" => ["zentinel.kdl"], "modified" => [], "removed" => []}]
      }

      assert {:ok, :ignored} = Webhooks.process_github_push(payload)
    end

    test "ignores push from unknown repo" do
      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "unknown/repo"},
        "head_commit" => %{"id" => "abc123", "message" => "test"},
        "commits" => [%{"added" => ["zentinel.kdl"], "modified" => [], "removed" => []}]
      }

      assert {:ok, :ignored} = Webhooks.process_github_push(payload)
    end

    test "ignores push when config file not changed" do
      _project =
        ZentinelCp.ProjectsFixtures.project_fixture(%{
          github_repo: "raskell-io/test-config",
          github_branch: "main",
          config_path: "zentinel.kdl"
        })

      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "raskell-io/test-config"},
        "head_commit" => %{"id" => "abc123", "message" => "readme update"},
        "commits" => [%{"added" => [], "modified" => ["README.md"], "removed" => []}]
      }

      assert {:ok, :ignored} = Webhooks.process_github_push(payload)
    end
  end
end
