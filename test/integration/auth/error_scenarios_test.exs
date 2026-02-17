defmodule ZentinelCpWeb.Integration.Auth.ErrorScenariosTest do
  @moduledoc """
  Integration tests for API error scenarios.

  Tests 401 (missing/invalid/expired/revoked key), 403 (insufficient scope),
  404 (not found), 409 (conflict), 422 (validation error).
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.Rollouts.Rollout

  @moduletag :integration

  # Helper to force rollout state for testing
  defp force_rollout_state(rollout, state) do
    rollout
    |> Rollout.state_changeset(state)
    |> ZentinelCp.Repo.update()
  end

  describe "401 Unauthorized errors" do
    test "missing Authorization header", %{conn: conn} do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      error_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/api/v1/projects/#{project.slug}/nodes")
        |> json_response!(401)

      assert error_resp["error"] =~ "Missing Authorization"
    end

    test "invalid API key", %{conn: conn} do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      error_resp =
        conn
        |> put_req_header("authorization", "Bearer invalid_key_12345")
        |> put_req_header("content-type", "application/json")
        |> get("/api/v1/projects/#{project.slug}/nodes")
        |> json_response!(401)

      assert error_resp["error"] =~ "Invalid or expired"
    end

    test "expired API key", %{conn: conn} do
      user = ZentinelCp.AccountsFixtures.user_fixture()
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      # Create an expired key
      {:ok, api_key} =
        ZentinelCp.Accounts.create_api_key(%{
          name: "expired-key",
          user_id: user.id,
          project_id: project.id,
          scopes: ["nodes:read"],
          expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      error_resp =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.key}")
        |> put_req_header("content-type", "application/json")
        |> get("/api/v1/projects/#{project.slug}/nodes")
        |> json_response!(401)

      assert error_resp["error"] =~ "Invalid or expired"
    end

    test "revoked API key", %{conn: conn} do
      user = ZentinelCp.AccountsFixtures.user_fixture()
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      {:ok, api_key} =
        ZentinelCp.Accounts.create_api_key(%{
          name: "revoked-key",
          user_id: user.id,
          project_id: project.id,
          scopes: ["nodes:read"]
        })

      # Revoke the key
      {:ok, _} = ZentinelCp.Accounts.revoke_api_key(api_key)

      error_resp =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.key}")
        |> put_req_header("content-type", "application/json")
        |> get("/api/v1/projects/#{project.slug}/nodes")
        |> json_response!(401)

      assert error_resp["error"] =~ "Invalid or expired"
    end

    test "malformed Authorization header", %{conn: conn} do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      error_resp =
        conn
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
        |> put_req_header("content-type", "application/json")
        |> get("/api/v1/projects/#{project.slug}/nodes")
        |> json_response!(401)

      assert error_resp["error"] =~ "Missing Authorization"
    end
  end

  describe "403 Forbidden errors" do
    test "insufficient scope returns 403 with required scope", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(403)

      assert error_resp["error"] =~ "Insufficient scope"
      assert error_resp["error"] =~ "nodes:read"
    end

    test "403 for write operation with read-only scope", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "forbidden-v1",
          config_source: "system { workers 1 }"
        })
        |> json_response!(403)

      assert error_resp["error"] =~ "bundles:write"
    end
  end

  describe "404 Not Found errors" do
    test "project not found", %{conn: conn} do
      {api_conn, _context} = setup_api_context(conn, scopes: [])

      error_resp =
        api_conn
        |> get("/api/v1/projects/nonexistent-project/nodes")
        |> json_response!(404)

      assert error_resp["error"] =~ "Project not found"
    end

    test "node not found", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      fake_id = Ecto.UUID.generate()

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/#{fake_id}")
        |> json_response!(404)

      assert error_resp["error"] =~ "Node not found"
    end

    test "bundle not found", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      fake_id = Ecto.UUID.generate()

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{fake_id}")
        |> json_response!(404)

      assert error_resp["error"] =~ "Bundle not found"
    end

    test "rollout not found", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read"])

      fake_id = Ecto.UUID.generate()

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts/#{fake_id}")
        |> json_response!(404)

      assert error_resp["error"] =~ "Rollout not found"
    end

    test "node in different project returns 404", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: [])

      # Create node in different project
      other_project = ZentinelCp.ProjectsFixtures.project_fixture()
      other_node = ZentinelCp.NodesFixtures.node_fixture(%{project: other_project})

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/#{other_node.id}")
        |> json_response!(404)

      assert error_resp["error"] =~ "Node not found"
    end
  end

  describe "409 Conflict errors" do
    test "bundle not yet compiled", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read", "bundles:write"])

      # Create bundle in pending state
      {:ok, bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: context.project.id,
          version: "conflict-v1",
          config_source: "system { workers 1 }"
        })

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/download")
        |> json_response!(409)

      assert error_resp["error"] =~ "not yet compiled"
    end

    test "bundle revoked", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read", "bundles:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})
      {:ok, _} = ZentinelCp.Bundles.revoke_bundle(bundle)

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/download")
        |> json_response!(409)

      assert error_resp["error"] =~ "revoked"
    end

    test "rollout cannot be paused in current state", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{project: context.project, bundle: bundle})

      # Force to completed state
      {:ok, _} = force_rollout_state(rollout, "completed")

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout.id}/pause")
        |> json_response!(409)

      assert error_resp["error"] =~ "cannot be paused"
    end

    test "rollout requires compiled bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:write", "bundles:write"])

      # Create pending bundle
      {:ok, bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: context.project.id,
          version: "rollout-conflict-v1",
          config_source: "system { workers 1 }"
        })

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id
        })
        |> json_response!(409)

      assert error_resp["error"] =~ "compiled"
    end

    test "drift event already resolved", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{node: node, project: context.project})

      # Resolve the event
      {:ok, _} = ZentinelCp.Nodes.resolve_drift_event(event, "manual")

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/drift/#{event.id}/resolve")
        |> json_response!(409)

      assert error_resp["error"] =~ "already resolved"
    end
  end

  describe "422 Unprocessable Entity errors" do
    test "bundle version already exists", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      # Create first bundle
      api_conn
      |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
        version: "duplicate-v1",
        config_source: "system { workers 1 }"
      })
      |> json_response!(201)

      # Try duplicate
      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "duplicate-v1",
          config_source: "system { workers 2 }"
        })
        |> json_response!(422)

      # Error may be on version or project_id (unique constraint)
      assert error_resp["error"]
      assert error_resp["error"]["version"] || error_resp["error"]["project_id"]
    end

    test "missing required fields", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{})
        |> json_response!(422)

      assert error_resp["error"]
    end

    test "node registration without name", %{conn: conn} do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      error_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{project.slug}/nodes/register", %{
          version: "1.0.0"
        })
        |> json_response!(422)

      assert error_resp["error"]
    end
  end

  describe "node authentication errors" do
    test "heartbeat without node auth", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      error_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{})
        |> json_response!(401)

      assert error_resp["error"]
    end

    test "heartbeat with invalid node key", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      error_resp =
        conn
        |> put_req_header("authorization", "Bearer invalid_node_key")
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{})
        |> json_response!(401)

      assert error_resp["error"]
    end
  end
end
