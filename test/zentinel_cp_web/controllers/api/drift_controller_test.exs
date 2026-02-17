defmodule ZentinelCpWeb.Api.DriftControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  alias ZentinelCp.Nodes

  setup do
    project = project_fixture()
    {conn, _api_key} = authenticate_api(build_conn(), project: project)

    {:ok, conn: conn, project: project}
  end

  describe "GET /api/v1/projects/:slug/drift" do
    test "lists drift events", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      _event1 = drift_event_fixture(%{node: node, project: project})
      _event2 = drift_event_fixture(%{node: node, project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/drift")

      assert %{"drift_events" => events, "total" => 2} = json_response(conn, 200)
      assert length(events) == 2
    end

    test "filters by active status", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      active = drift_event_fixture(%{node: node, project: project})
      resolved = drift_event_fixture(%{node: node, project: project})
      Nodes.resolve_drift_event(resolved, "manual")

      conn = get(conn, "/api/v1/projects/#{project.slug}/drift?status=active")

      assert %{"drift_events" => events, "total" => 1} = json_response(conn, 200)
      assert hd(events)["id"] == active.id
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, "/api/v1/projects/nonexistent/drift")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "GET /api/v1/projects/:slug/drift/stats" do
    test "returns drift statistics", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      _event = drift_event_fixture(%{node: node, project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/drift/stats")

      assert %{
               "total_managed" => _,
               "drifted" => _,
               "in_sync" => _,
               "active_events" => 1,
               "resolved_today" => 0
             } = json_response(conn, 200)
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, "/api/v1/projects/nonexistent/drift/stats")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "GET /api/v1/projects/:slug/drift/:id" do
    test "shows a drift event", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      event = drift_event_fixture(%{node: node, project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/drift/#{event.id}")

      assert %{"drift_event" => returned} = json_response(conn, 200)
      assert returned["id"] == event.id
      assert returned["node_id"] == node.id
      assert returned["expected_bundle_id"] == event.expected_bundle_id
    end

    test "returns 404 for unknown event", %{conn: conn, project: project} do
      conn = get(conn, "/api/v1/projects/#{project.slug}/drift/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 404 for event from different project", %{conn: conn, project: project} do
      other_project = project_fixture()
      node = node_fixture(%{project: other_project})
      event = drift_event_fixture(%{node: node, project: other_project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/drift/#{event.id}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/v1/projects/:slug/drift/:id/resolve" do
    test "resolves a drift event", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      event = drift_event_fixture(%{node: node, project: project})

      conn = post(conn, "/api/v1/projects/#{project.slug}/drift/#{event.id}/resolve")

      assert %{"drift_event" => returned} = json_response(conn, 200)
      assert returned["resolution"] == "manual"
      assert returned["resolved_at"] != nil
    end

    test "returns 409 for already resolved event", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      event = drift_event_fixture(%{node: node, project: project})
      Nodes.resolve_drift_event(event, "manual")

      conn = post(conn, "/api/v1/projects/#{project.slug}/drift/#{event.id}/resolve")

      assert json_response(conn, 409)["error"] =~ "already resolved"
    end

    test "returns 404 for unknown event", %{conn: conn, project: project} do
      conn = post(conn, "/api/v1/projects/#{project.slug}/drift/#{Ecto.UUID.generate()}/resolve")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/v1/projects/:slug/drift/resolve-all" do
    test "resolves all active drift events", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      _event1 = drift_event_fixture(%{node: node, project: project})
      _event2 = drift_event_fixture(%{node: node, project: project})

      conn = post(conn, "/api/v1/projects/#{project.slug}/drift/resolve-all")

      assert %{"resolved_count" => 2} = json_response(conn, 200)
    end

    test "returns 0 when no active events", %{conn: conn, project: project} do
      conn = post(conn, "/api/v1/projects/#{project.slug}/drift/resolve-all")
      assert %{"resolved_count" => 0} = json_response(conn, 200)
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = post(conn, "/api/v1/projects/nonexistent/drift/resolve-all")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end
end
