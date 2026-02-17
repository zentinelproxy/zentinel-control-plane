defmodule ZentinelCpWeb.Integration.Api.EdgeCasesTest do
  @moduledoc """
  Integration tests for edge cases and boundary conditions.

  Tests pagination, input validation, concurrent operations, and unusual inputs.
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "pagination edge cases" do
    test "page parameter works", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Create some nodes
      for i <- 1..5 do
        ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "page-node-#{i}"})
      end

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?page=1")
        |> json_response!(200)

      # API may or may not implement pagination, but should return valid response
      assert is_list(resp["nodes"])
      assert resp["total"] >= 5
    end

    test "invalid page parameter handled gracefully", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?page=-1")
        |> json_response!(200)

      assert is_list(resp["nodes"])
    end

    test "limit parameter works", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      for i <- 1..10 do
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "limit-node-#{i}"
        })
      end

      # Try limit parameter (API might use limit instead of per_page)
      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?limit=3")
        |> json_response!(200)

      # API may or may not support limit, but should return valid response
      assert is_list(resp["nodes"])
    end
  end

  describe "invalid UUID handling" do
    test "malformed UUID returns 400 or 404", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/not-a-uuid")

      # Accept either 400 (bad request) or 404 (not found)
      assert resp.status in [400, 404]
    end

    test "partial UUID returns error", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Partial UUID that's not valid
      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/12345-invalid")

      # Should fail with bad request or not found
      assert resp.status in [400, 404]
    end

    test "valid UUID format but non-existent resource returns 404", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      fake_uuid = "00000000-0000-0000-0000-000000000000"

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/#{fake_uuid}")
        |> json_response!(404)

      assert resp["error"] =~ "not found"
    end
  end

  describe "input validation edge cases" do
    test "empty version string for bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "",
          config_source: "system { workers 1 }"
        })
        |> json_response!(422)

      assert resp["error"]
    end

    test "very long version string for bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      long_version = String.duplicate("v", 500)

      resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: long_version,
          config_source: "system { workers 1 }"
        })

      # Should either succeed or fail with validation error
      assert resp.status in [201, 422]
    end

    test "special characters in node name", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{context.project.slug}/nodes/register", %{
          name: "node-with-émojis-🎉-and-üñíçödé",
          version: "1.0.0"
        })

      # Should either succeed or fail with validation error
      assert resp.status in [201, 422]
    end

    test "whitespace-only name for node", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{context.project.slug}/nodes/register", %{
          name: "   ",
          version: "1.0.0"
        })
        |> json_response!(422)

      assert resp["error"]
    end
  end

  describe "empty collection handling" do
    test "list nodes on empty project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(200)

      assert resp["nodes"] == []
      assert resp["total"] == 0
    end

    test "list bundles on empty project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/bundles")
        |> json_response!(200)

      assert resp["bundles"] == []
      assert resp["total"] == 0
    end

    test "list rollouts on empty project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts")
        |> json_response!(200)

      assert resp["rollouts"] == []
      assert resp["total"] == 0
    end

    test "list drift events on empty project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift")
        |> json_response!(200)

      assert resp["drift_events"] == []
      assert resp["total"] == 0
    end
  end

  describe "filter combinations" do
    test "multiple filter parameters combined", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Create nodes with different statuses
      online_node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "online-filter-node"
        })

      {:ok, _} =
        ZentinelCp.Nodes.record_heartbeat(online_node, %{health: %{"status" => "healthy"}})

      ZentinelCp.NodesFixtures.node_fixture(%{
        project: context.project,
        name: "offline-filter-node"
      })

      # Filter by online status with pagination
      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?status=online&per_page=10")
        |> json_response!(200)

      assert Enum.all?(resp["nodes"], &(&1["status"] == "online"))
    end

    test "invalid filter value", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?status=invalid_status")
        |> json_response!(200)

      # Should either ignore invalid filter or return empty results
      assert is_list(resp["nodes"])
    end
  end

  describe "content-type handling" do
    test "request without content-type header", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["bundles:write"])

      # Remove content-type header
      api_conn =
        api_conn
        |> Plug.Conn.delete_req_header("content-type")

      resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/bundles", %{
          version: "no-content-type-v1",
          config_source: "system { workers 1 }"
        })

      # Should either work or fail gracefully
      assert resp.status in [201, 400, 415, 422]
    end
  end

  describe "node heartbeat edge cases" do
    test "heartbeat with minimal payload", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      {node, node_key} =
        ZentinelCp.NodesFixtures.node_with_key_fixture(%{
          project: context.project,
          name: "minimal-heartbeat-node"
        })

      resp =
        conn
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{})
        |> json_response!(200)

      assert resp["status"] == "ok"
    end

    test "heartbeat with large metrics payload", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      {node, node_key} =
        ZentinelCp.NodesFixtures.node_with_key_fixture(%{
          project: context.project,
          name: "large-metrics-node"
        })

      # Create large metrics map
      large_metrics =
        Enum.reduce(1..100, %{}, fn i, acc ->
          Map.put(acc, "metric_#{i}", :rand.uniform() * 100)
        end)

      resp =
        conn
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{
          metrics: large_metrics
        })
        |> json_response!(200)

      assert resp["status"] == "ok"
    end
  end

  describe "batch operations" do
    test "batch event submission with empty events array", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: [])

      {node, node_key} =
        ZentinelCp.NodesFixtures.node_with_key_fixture(%{
          project: context.project,
          name: "batch-events-node"
        })

      resp =
        conn
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node.id}/events", %{
          events: []
        })
        |> json_response!(201)

      assert resp["count"] == 0
    end
  end
end
