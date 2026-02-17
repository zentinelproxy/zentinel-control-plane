defmodule ZentinelCpWeb.Integration.Api.DriftWorkflowTest do
  @moduledoc """
  Integration tests for drift detection API workflows.

  Tests the complete workflow: list events → resolve → verify resolved
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "drift events listing" do
    test "list drift events for project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      # Create drift events
      ZentinelCp.NodesFixtures.drift_event_fixture(%{
        node: node,
        project: context.project,
        severity: "high"
      })

      ZentinelCp.NodesFixtures.drift_event_fixture(%{
        node: node,
        project: context.project,
        severity: "medium"
      })

      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift")
        |> json_response!(200)

      assert list_resp["total"] >= 2
      assert is_list(list_resp["drift_events"])

      event = List.first(list_resp["drift_events"])
      assert event["id"]
      assert event["node_id"] == node.id
      assert event["severity"]
    end

    test "filter by status", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      # Create active event
      active_event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })

      # Create and resolve another event
      resolved_event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })

      {:ok, _} = ZentinelCp.Nodes.resolve_drift_event(resolved_event, "manual")

      # List only active
      active_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift?status=active")
        |> json_response!(200)

      active_ids = Enum.map(active_resp["drift_events"], & &1["id"])
      assert active_event.id in active_ids
      refute resolved_event.id in active_ids
    end
  end

  describe "drift event resolution" do
    test "resolve single drift event", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })

      resolve_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/drift/#{event.id}/resolve")
        |> json_response!(200)

      assert resolve_resp["drift_event"]["resolved_at"]
      assert resolve_resp["drift_event"]["resolution"] == "manual"
    end

    test "cannot resolve already resolved event", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })

      # Resolve first time
      {:ok, _} = ZentinelCp.Nodes.resolve_drift_event(event, "manual")

      # Try to resolve again
      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/drift/#{event.id}/resolve")
        |> json_response!(409)

      assert error_resp["error"] =~ "already resolved"
    end

    test "resolve all drift events", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read", "nodes:write"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      # Create multiple events
      for _ <- 1..3 do
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project
        })
      end

      resolve_all_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/drift/resolve-all")
        |> json_response!(200)

      assert resolve_all_resp["resolved_count"] >= 3

      # Verify all resolved
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift?status=active")
        |> json_response!(200)

      assert list_resp["total"] == 0
    end
  end

  describe "drift statistics" do
    test "get drift stats for project", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      ZentinelCp.NodesFixtures.drift_event_fixture(%{
        node: node,
        project: context.project
      })

      stats_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift/stats")
        |> json_response!(200)

      assert is_integer(stats_resp["total_managed"])
      assert is_integer(stats_resp["drifted"])
      assert is_integer(stats_resp["in_sync"])
      assert is_integer(stats_resp["active_events"])
    end
  end

  describe "drift event details" do
    test "show single drift event", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project,
          severity: "critical"
        })

      show_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift/#{event.id}")
        |> json_response!(200)

      assert show_resp["drift_event"]["id"] == event.id
      assert show_resp["drift_event"]["severity"] == "critical"
      assert show_resp["drift_event"]["node_id"] == node.id
    end

    test "404 for non-existent event", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      fake_id = Ecto.UUID.generate()

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift/#{fake_id}")
        |> json_response!(404)

      assert error_resp["error"] =~ "not found"
    end
  end

  describe "drift export" do
    test "export drift events as JSON", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      ZentinelCp.NodesFixtures.drift_event_fixture(%{
        node: node,
        project: context.project
      })

      export_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift/export?format=json")

      assert export_resp.status == 200
      [content_type] = get_resp_header(export_resp, "content-type")
      assert content_type =~ "application/json"

      body = json_response!(export_resp, 200)
      assert body["exported_at"]
      assert body["project"]["slug"] == context.project.slug
      assert is_list(body["drift_events"])
    end

    test "export drift events as CSV", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["nodes:read"])

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})

      ZentinelCp.NodesFixtures.drift_event_fixture(%{
        node: node,
        project: context.project
      })

      export_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/drift/export?format=csv")

      assert export_resp.status == 200
      [content_type] = get_resp_header(export_resp, "content-type")
      assert content_type =~ "text/csv"

      body = export_resp.resp_body
      assert body =~ "id,node_id"
    end
  end
end
