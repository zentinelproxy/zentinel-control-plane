defmodule ZentinelCpWeb.Integration.Auth.ScopeEnforcementTest do
  @moduledoc """
  Integration tests for API scope enforcement.

  Tests read vs write scopes, empty scopes (legacy full access),
  and multi-scope combinations.
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "read vs write scopes" do
    setup %{conn: conn} do
      {_conn, context} = setup_api_context(conn, scopes: [])

      # Create scoped keys
      keys =
        setup_scoped_keys(conn, context.project, context.user, %{
          read_only: ["nodes:read", "bundles:read", "rollouts:read"],
          write_only: ["nodes:write", "bundles:write", "rollouts:write"],
          full: []
        })

      %{context: context, keys: keys}
    end

    test "read-only key can list nodes but not delete", %{keys: keys, context: context} do
      {read_conn, _} = keys.read_only

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      # Can read
      list_resp =
        read_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(200)

      assert list_resp["total"] >= 1

      # Cannot delete
      error_resp =
        read_conn
        |> delete("/api/v1/projects/#{context.project.slug}/nodes/#{node.id}")
        |> json_response!(403)

      assert error_resp["error"] =~ "Insufficient scope"
      assert error_resp["error"] =~ "nodes:write"
    end

    test "write-only key cannot list nodes", %{keys: keys, context: context} do
      {write_conn, _} = keys.write_only

      ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      error_resp =
        write_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(403)

      assert error_resp["error"] =~ "Insufficient scope"
      assert error_resp["error"] =~ "nodes:read"
    end

    test "write-only key can delete nodes", %{keys: keys, context: context} do
      {write_conn, _} = keys.write_only

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      write_conn
      |> delete("/api/v1/projects/#{context.project.slug}/nodes/#{node.id}")
      |> response(204)
    end

    test "read-only key can list bundles but not create", %{keys: keys, context: context} do
      {read_conn, _} = keys.read_only

      # Can read
      list_resp =
        read_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles")
        |> json_response!(200)

      assert is_list(list_resp["bundles"])

      # Cannot create
      error_resp =
        read_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "1.0.0",
          config_source: "system { workers 1 }"
        })
        |> json_response!(403)

      assert error_resp["error"] =~ "bundles:write"
    end

    test "read-only key can list rollouts but not create", %{keys: keys, context: context} do
      {read_conn, _} = keys.read_only

      # Can read
      list_resp =
        read_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts")
        |> json_response!(200)

      assert is_list(list_resp["rollouts"])

      # Cannot create
      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      error_resp =
        read_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id
        })
        |> json_response!(403)

      assert error_resp["error"] =~ "rollouts:write"
    end
  end

  describe "empty scopes (legacy full access)" do
    test "legacy key with empty scopes has full access", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: [])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      # Can read
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/nodes")
      |> json_response!(200)

      # Can delete
      api_conn
      |> delete("/api/v1/projects/#{context.project.slug}/nodes/#{node.id}")
      |> response(204)
    end
  end

  describe "multi-scope keys" do
    test "key with multiple scopes can access all granted resources", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["nodes:read", "bundles:read", "rollouts:read"])

      # Can read nodes
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/nodes")
      |> json_response!(200)

      # Can read bundles
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/bundles")
      |> json_response!(200)

      # Can read rollouts
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/rollouts")
      |> json_response!(200)
    end

    test "partial scope grants partial access", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "bundles:write"])

      # Can read nodes
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/nodes")
      |> json_response!(200)

      # Cannot read bundles (only has write)
      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles")
        |> json_response!(403)

      assert error_resp["error"] =~ "bundles:read"

      # Can create bundles
      api_conn
      |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
        version: "multi-scope-v1",
        config_source: "system { workers 1 }"
      })
      |> json_response!(201)
    end
  end

  describe "project scoping" do
    test "key scoped to project cannot access other projects", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Create another project
      other_org = ZentinelCp.OrgsFixtures.org_fixture()
      other_project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: other_org})

      # Cannot access other project
      error_resp =
        api_conn
        |> get("/api/v1/projects/#{other_project.slug}/nodes")
        |> json_response!(404)

      assert error_resp["error"] =~ "not found"

      # Can access own project
      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/nodes")
      |> json_response!(200)
    end
  end

  describe "drift scope enforcement" do
    test "nodes:read scope grants drift read access", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/drift")
      |> json_response!(200)
    end

    test "nodes:write scope required for drift resolution", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/drift/#{event.id}/resolve")
        |> json_response!(403)

      assert error_resp["error"] =~ "nodes:write"
    end
  end
end
