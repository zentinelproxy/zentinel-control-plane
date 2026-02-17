defmodule ZentinelCpWeb.Api.ProjectNodesControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  setup %{conn: conn} do
    project = project_fixture()
    {conn, _api_key} = authenticate_api(conn, project: project)
    {:ok, conn: conn, project: project}
  end

  describe "GET /api/v1/projects/:slug/nodes" do
    test "lists nodes for a project", %{conn: conn, project: project} do
      node = node_fixture(%{project: project, name: "proxy-1"})

      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes")

      assert %{"nodes" => nodes, "total" => 1} = json_response(conn, 200)
      assert [%{"id" => id, "name" => "proxy-1"}] = nodes
      assert id == node.id
    end

    test "returns empty list for project with no nodes", %{conn: conn, project: project} do
      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes")

      assert %{"nodes" => [], "total" => 0} = json_response(conn, 200)
    end

    test "filters by status", %{conn: conn, project: project} do
      node_fixture(%{project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes?status=offline")

      assert %{"nodes" => [], "total" => 0} = json_response(conn, 200)
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn = get(conn, "/api/v1/projects/nonexistent/nodes")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 401 without auth header" do
      conn = build_conn()
      conn = get(conn, "/api/v1/projects/test/nodes")
      assert json_response(conn, 401)["error"] =~ "Missing"
    end
  end

  describe "GET /api/v1/projects/:slug/nodes/:id" do
    test "shows a node", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes/#{node.id}")

      assert %{"node" => %{"id" => id}} = json_response(conn, 200)
      assert id == node.id
    end

    test "returns 404 for unknown node", %{conn: conn, project: project} do
      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 404 for node in different project", %{conn: conn, project: project} do
      other_project = project_fixture()
      node = node_fixture(%{project: other_project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes/#{node.id}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "GET /api/v1/projects/:slug/nodes/stats" do
    test "returns node stats", %{conn: conn, project: project} do
      node_fixture(%{project: project})

      conn = get(conn, "/api/v1/projects/#{project.slug}/nodes/stats")

      assert %{"total" => 1, "by_status" => %{"online" => 1}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/v1/projects/:slug/nodes/:id" do
    test "deletes a node", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})

      conn = delete(conn, "/api/v1/projects/#{project.slug}/nodes/#{node.id}")

      assert response(conn, 204)
      refute ZentinelCp.Nodes.get_node(node.id)
    end

    test "returns 404 for unknown node", %{conn: conn, project: project} do
      conn = delete(conn, "/api/v1/projects/#{project.slug}/nodes/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end
end
