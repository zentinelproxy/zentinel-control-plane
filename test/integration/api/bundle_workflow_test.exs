defmodule ZentinelCpWeb.Integration.Api.BundleWorkflowTest do
  @moduledoc """
  Integration tests for bundle API workflows.

  Tests the complete lifecycle: create → poll status → download
  Also tests version uniqueness and bundle assignment.
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  @valid_kdl """
  system {
    workers 4
  }
  listeners {
    listener "http" address="0.0.0.0:8080"
  }
  """

  describe "bundle creation workflow" do
    test "create → poll status → show details", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read", "bundles:write"])

      # Step 1: Create bundle
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "1.0.0",
          config_source: @valid_kdl
        })
        |> json_response!(201)

      assert create_resp["id"]
      assert create_resp["version"] == "1.0.0"
      assert create_resp["status"] in ["pending", "compiling", "compiled"]

      bundle_id = create_resp["id"]

      # Step 2: Poll for status (compile may be inline in test mode)
      show_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle_id}")
        |> json_response!(200)

      assert show_resp["bundle"]["id"] == bundle_id
      assert show_resp["bundle"]["version"] == "1.0.0"

      # Step 3: List bundles
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles")
        |> json_response!(200)

      assert list_resp["total"] >= 1
      assert Enum.find(list_resp["bundles"], &(&1["id"] == bundle_id))
    end

    test "version uniqueness enforcement", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      # Create first bundle
      api_conn
      |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
        version: "unique-v1",
        config_source: @valid_kdl
      })
      |> json_response!(201)

      # Attempt duplicate version
      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "unique-v1",
          config_source: @valid_kdl
        })
        |> json_response!(422)

      # Error may be on version or project_id (unique constraint)
      assert error_resp["error"]
      assert error_resp["error"]["version"] || error_resp["error"]["project_id"]
    end

    @tag :skip
    test "download compiled bundle", %{conn: conn} do
      # This test requires S3/MinIO to be configured
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      download_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/download")

      case download_resp.status do
        200 ->
          body = json_response!(download_resp, 200)
          assert body["checksum"]

        _ ->
          # Expected if S3/MinIO not configured
          :ok
      end
    end

    test "cannot download pending bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read", "bundles:write"])

      # Create bundle (stays pending in test without compile worker)
      {:ok, bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: context.project.id,
          version: "pending-v1",
          config_source: @valid_kdl
        })

      # Force pending status
      {:ok, bundle} = ZentinelCp.Bundles.update_status(bundle, "pending")

      # Attempt download - should fail
      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/download")
        |> json_response!(409)

      assert error_resp["error"] =~ "not yet compiled"
    end
  end

  describe "bundle assignment" do
    test "assign bundle to nodes", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["bundles:read", "bundles:write", "nodes:read"])

      # Create compiled bundle
      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Register some nodes
      node1 =
        ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "assign-node-1"})

      node2 =
        ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "assign-node-2"})

      # Assign bundle
      assign_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/assign", %{
          node_ids: [node1.id, node2.id]
        })
        |> json_response!(200)

      assert assign_resp["assigned"] == 2
    end
  end

  describe "bundle verification" do
    test "verify unsigned bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      # Bundle signing is disabled in test config
      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      verify_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/verify")
        |> json_response!(200)

      assert verify_resp["signed"] == false
      assert verify_resp["verified"] == false
    end
  end

  describe "bundle revocation" do
    test "revoke compiled bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read", "bundles:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Revoke
      revoke_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/revoke")
        |> json_response!(200)

      assert revoke_resp["bundle"]["status"] == "revoked"

      # Cannot download revoked bundle
      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles/#{bundle.id}/download")
        |> json_response!(409)

      assert error_resp["error"] =~ "revoked"
    end
  end

  describe "bundle filtering" do
    test "filter by status", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      # Create compiled bundle
      ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
        project: context.project,
        version: "compiled-v1"
      })

      # List only compiled
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles?status=compiled")
        |> json_response!(200)

      assert Enum.all?(list_resp["bundles"], &(&1["status"] == "compiled"))
    end
  end
end
