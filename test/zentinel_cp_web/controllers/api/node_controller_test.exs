defmodule ZentinelCpWeb.Api.NodeControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  setup do
    project = project_fixture()
    {:ok, project: project}
  end

  describe "POST /api/v1/projects/:slug/nodes/register" do
    test "registers a new node", %{conn: conn, project: project} do
      conn =
        post(conn, "/api/v1/projects/#{project.slug}/nodes/register", %{
          "name" => "proxy-1",
          "version" => "0.4.7",
          "labels" => %{"env" => "test"}
        })

      assert %{"node_id" => node_id, "node_key" => node_key} = json_response(conn, 201)
      assert is_binary(node_id)
      assert is_binary(node_key)
    end

    test "returns 404 for unknown project", %{conn: conn} do
      conn =
        post(conn, "/api/v1/projects/nonexistent/nodes/register", %{
          "name" => "proxy-1"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 422 for invalid node name", %{conn: conn, project: project} do
      conn =
        post(conn, "/api/v1/projects/#{project.slug}/nodes/register", %{
          "name" => "-invalid"
        })

      assert json_response(conn, 422)["error"]
    end

    test "returns 422 for duplicate node name", %{conn: conn, project: project} do
      node_fixture(%{project: project, name: "proxy-1"})

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/nodes/register", %{
          "name" => "proxy-1"
        })

      assert json_response(conn, 422)["error"]
    end
  end

  describe "POST /api/v1/nodes/:node_id/heartbeat" do
    test "records heartbeat with valid key", %{conn: conn} do
      {node, key} = node_with_key_fixture()

      conn =
        conn
        |> put_req_header("x-zentinel-node-key", key)
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{
          "version" => "0.4.8",
          "health" => %{"cpu" => 42},
          "metrics" => %{"rps" => 100}
        })

      assert %{"status" => "ok"} = json_response(conn, 200)
    end

    test "returns 401 without key", %{conn: conn} do
      {node, _key} = node_with_key_fixture()

      conn = post(conn, "/api/v1/nodes/#{node.id}/heartbeat", %{})

      assert json_response(conn, 401)["error"] =~ "Missing"
    end

    test "returns 401 with invalid key", %{conn: conn} do
      {node, _key} = node_with_key_fixture()

      conn =
        conn
        |> put_req_header("x-zentinel-node-key", "bogus")
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{})

      assert json_response(conn, 401)["error"] =~ "Invalid"
    end
  end

  describe "GET /api/v1/nodes/:node_id/bundles/latest" do
    test "returns no_update stub", %{conn: conn} do
      {node, key} = node_with_key_fixture()

      conn =
        conn
        |> put_req_header("x-zentinel-node-key", key)
        |> get("/api/v1/nodes/#{node.id}/bundles/latest")

      assert %{"no_update" => true} = json_response(conn, 200)
    end
  end
end
