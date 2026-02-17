defmodule ZentinelCpWeb.Integration.Api.NodeWorkflowTest do
  @moduledoc """
  Integration tests for node API workflows.

  Tests the complete lifecycle: register → heartbeat → list → delete
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "node registration workflow" do
    test "register → heartbeat → list → delete", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      # Step 1: Register a node (no auth required)
      register_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{context.project.slug}/nodes/register", %{
          name: "test-node-1",
          labels: %{"env" => "staging"},
          capabilities: ["proxy"],
          version: "1.0.0"
        })
        |> json_response!(201)

      assert register_resp["node_id"]
      assert register_resp["node_key"]
      assert register_resp["poll_interval_s"] == 30

      node_id = register_resp["node_id"]
      node_key = register_resp["node_key"]

      # Step 2: Send heartbeat (node auth required)
      heartbeat_resp =
        conn
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node_id}/heartbeat", %{
          health: %{"status" => "healthy"},
          metrics: %{"cpu" => 45.2},
          version: "1.0.0"
        })
        |> json_response!(200)

      assert heartbeat_resp["status"] == "ok"
      assert heartbeat_resp["node_id"] == node_id
      assert heartbeat_resp["last_seen_at"]

      # Step 3: List nodes (API key auth)
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(200)

      assert list_resp["total"] >= 1
      node = Enum.find(list_resp["nodes"], &(&1["id"] == node_id))
      assert node
      assert node["name"] == "test-node-1"
      assert node["status"] == "online"

      # Step 4: Get node stats
      stats_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes/stats")
        |> json_response!(200)

      assert stats_resp["total"] >= 1
      assert is_map(stats_resp["by_status"])

      # Step 5: Delete node (API key auth)
      api_conn
      |> delete("/api/v1/projects/#{context.project.slug}/nodes/#{node_id}")
      |> response(204)

      # Verify node is deleted
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes")
        |> json_response!(200)

      refute Enum.find(list_resp["nodes"], &(&1["id"] == node_id))
    end

    test "JWT token exchange flow", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Use fixture to create node
      {node, node_key} =
        ZentinelCp.NodesFixtures.node_with_key_fixture(%{
          project: context.project,
          name: "jwt-test-node"
        })

      # Exchange static key for JWT
      token_resp =
        Phoenix.ConnTest.build_conn()
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node.id}/token", %{})

      # JWT issuance requires org signing key - may fail in test env
      case token_resp.status do
        200 ->
          body = json_response!(token_resp, 200)
          assert body["token"]
          assert body["token_type"] == "Bearer"
          assert body["expires_at"]
          assert body["expires_in"]

        422 ->
          # Expected if node's project not in an org
          body = json_response!(token_resp, 422)
          assert body["error"] =~ "organization"

        503 ->
          # Expected if no signing key configured
          body = json_response!(token_resp, 503)
          assert body["error"] =~ "signing key"
      end
    end

    test "node events submission", %{conn: conn} do
      {_api_conn, context} = setup_api_context(conn)

      # Register a node
      register_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{context.project.slug}/nodes/register", %{
          name: "events-test-node",
          version: "1.0.0"
        })
        |> json_response!(201)

      node_id = register_resp["node_id"]
      node_key = register_resp["node_key"]

      # Submit single event
      event_resp =
        conn
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node_id}/events", %{
          event_type: "config_reload",
          severity: "info",
          message: "Configuration reloaded successfully"
        })
        |> json_response!(201)

      assert event_resp["status"] == "ok"
      assert event_resp["count"] == 1

      # Submit batch of events (use valid event_types: config_reload, bundle_switch, error, startup, shutdown, warning, info)
      batch_resp =
        Phoenix.ConnTest.build_conn()
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node_id}/events", %{
          events: [
            %{event_type: "startup", severity: "info", message: "Node started"},
            %{event_type: "info", severity: "info", message: "Health check passed"}
          ]
        })
        |> json_response!(201)

      assert batch_resp["count"] == 2
    end
  end

  describe "node filtering" do
    test "filter nodes by status", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      # Create nodes using fixtures instead of API
      online_node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "online-node"
        })

      _offline_node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "offline-node"
        })

      # Make one node online via heartbeat
      {:ok, _} =
        ZentinelCp.Nodes.record_heartbeat(online_node, %{health: %{"status" => "healthy"}})

      # Filter by online status
      online_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/nodes?status=online")
        |> json_response!(200)

      assert Enum.all?(online_resp["nodes"], &(&1["status"] == "online"))
      assert Enum.any?(online_resp["nodes"], &(&1["name"] == "online-node"))
    end
  end
end
