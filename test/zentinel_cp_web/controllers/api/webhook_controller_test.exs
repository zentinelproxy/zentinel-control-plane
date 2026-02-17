defmodule ZentinelCpWeb.Api.WebhookControllerTest do
  use ZentinelCpWeb.ConnCase

  import Mox

  @secret "test_webhook_secret"

  setup :verify_on_exit!

  defp sign_payload(payload) do
    mac =
      :crypto.mac(:hmac, :sha256, @secret, payload)
      |> Base.encode16(case: :lower)

    "sha256=" <> mac
  end

  defp push_payload(repo, branch, sha, changed_files) do
    Jason.encode!(%{
      ref: "refs/heads/#{branch}",
      repository: %{full_name: repo},
      head_commit: %{id: sha, message: "test commit"},
      commits: [
        %{added: changed_files, modified: [], removed: []}
      ]
    })
  end

  describe "POST /api/v1/webhooks/github" do
    test "creates bundle for valid push event with matching project", %{conn: conn} do
      _project =
        ZentinelCp.ProjectsFixtures.project_fixture(%{
          github_repo: "raskell-io/webhook-test",
          github_branch: "main",
          config_path: "zentinel.kdl"
        })

      expect(ZentinelCp.Webhooks.GitHubClient.Mock, :fetch_file, fn
        "raskell-io/webhook-test", "deadbeef12345678", "zentinel.kdl" ->
          "system { workers 4 }"
      end)

      payload =
        push_payload("raskell-io/webhook-test", "main", "deadbeef12345678", ["zentinel.kdl"])

      signature = sign_payload(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_req_header("x-github-event", "push")
        |> post("/api/v1/webhooks/github", payload)

      assert %{"status" => "ok", "bundle_id" => bundle_id} = json_response(conn, 201)
      assert is_binary(bundle_id)
    end

    test "returns 401 for invalid signature", %{conn: conn} do
      payload = push_payload("raskell-io/test", "main", "abc123", ["zentinel.kdl"])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=invalid")
        |> put_req_header("x-github-event", "push")
        |> post("/api/v1/webhooks/github", payload)

      assert json_response(conn, 401)["error"] == "Invalid signature"
    end

    test "returns 401 for missing signature", %{conn: conn} do
      payload = push_payload("raskell-io/test", "main", "abc123", ["zentinel.kdl"])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "push")
        |> post("/api/v1/webhooks/github", payload)

      assert json_response(conn, 401)["error"] == "Missing signature"
    end

    test "returns 200 ok for non-push events", %{conn: conn} do
      payload = Jason.encode!(%{action: "opened", pull_request: %{number: 1}})
      signature = sign_payload(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_req_header("x-github-event", "pull_request")
        |> post("/api/v1/webhooks/github", payload)

      assert %{"status" => "ok", "message" => msg} = json_response(conn, 200)
      assert msg =~ "ignored"
    end

    test "returns 200 ok for unknown repo", %{conn: conn} do
      payload = push_payload("unknown/repo", "main", "abc123", ["zentinel.kdl"])
      signature = sign_payload(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", signature)
        |> put_req_header("x-github-event", "push")
        |> post("/api/v1/webhooks/github", payload)

      assert %{"status" => "ok", "message" => msg} = json_response(conn, 200)
      assert msg =~ "ignored"
    end
  end
end
