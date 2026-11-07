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

defmodule ZentinelCpWeb.Api.NodeBundleDownloadTest do
  use ZentinelCpWeb.ConnCase, async: false

  import ZentinelCp.NodesFixtures

  import Ecto.Query

  alias ZentinelCp.{Bundles, Repo}
  alias ZentinelCp.Nodes.Node

  setup do
    {node, key} = node_with_key_fixture()
    project = ZentinelCp.Projects.get_project(node.project_id)
    bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: project})
    storage_key = "test/#{bundle.id}.tar.zst"
    :ok = Bundles.Storage.upload(storage_key, "archive-bytes")

    checksum = :crypto.hash(:sha256, "archive-bytes") |> Base.encode16(case: :lower)

    bundle =
      bundle
      |> Ecto.Changeset.change(storage_key: storage_key, checksum: checksum)
      |> Repo.update!()

    {:ok, node: node, key: key, bundle: bundle}
  end

  defp stage(node, bundle) do
    node |> Ecto.Changeset.change(staged_bundle_id: bundle.id) |> Repo.update!()
  end

  defp node_get(conn, key, path),
    do: conn |> put_req_header("x-zentinel-node-key", key) |> get(path)

  test "latest points the node at the control plane download", ctx do
    stage(ctx.node, ctx.bundle)

    body =
      ctx.conn
      |> node_get(ctx.key, "/api/v1/nodes/#{ctx.node.id}/bundles/latest")
      |> json_response(200)

    assert body["bundle_id"] == ctx.bundle.id

    assert body["download_path"] ==
             "/api/v1/nodes/#{ctx.node.id}/bundles/#{ctx.bundle.id}/download"
  end

  test "a staged bundle downloads", ctx do
    stage(ctx.node, ctx.bundle)
    path = "/api/v1/nodes/#{ctx.node.id}/bundles/#{ctx.bundle.id}/download"
    conn = node_get(ctx.conn, ctx.key, path)

    assert response(conn, 200) == "archive-bytes"
    assert get_resp_header(conn, "x-bundle-checksum") == [ctx.bundle.checksum]
  end

  test "a bundle not assigned to the node does not", ctx do
    path = "/api/v1/nodes/#{ctx.node.id}/bundles/#{ctx.bundle.id}/download"
    assert ctx.conn |> node_get(ctx.key, path) |> json_response(404)
  end

  test "another project's bundle does not, even if assigned", ctx do
    other = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture()

    Repo.update_all(from(n in Node, where: n.id == ^ctx.node.id),
      set: [staged_bundle_id: other.id]
    )

    path = "/api/v1/nodes/#{ctx.node.id}/bundles/#{other.id}/download"
    assert ctx.conn |> node_get(ctx.key, path) |> json_response(404)
  end

  test "requires node authentication", ctx do
    stage(ctx.node, ctx.bundle)
    path = "/api/v1/nodes/#{ctx.node.id}/bundles/#{ctx.bundle.id}/download"
    assert get(ctx.conn, path).status == 401
  end
end

defmodule ZentinelCpWeb.Api.NodeActiveBundleTest do
  use ZentinelCpWeb.ConnCase, async: false

  import ZentinelCp.NodesFixtures

  alias ZentinelCp.Nodes

  defp heartbeat(conn, node, key, active_bundle_id) do
    conn
    |> put_req_header("x-zentinel-node-key", key)
    |> post("/api/v1/nodes/#{node.id}/heartbeat", %{active_bundle_id: active_bundle_id})
    |> json_response(200)
  end

  test "a heartbeat records the bundle the node is running", %{conn: conn} do
    {node, key} = node_with_key_fixture()
    project = ZentinelCp.Projects.get_project(node.project_id)
    bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: project})

    heartbeat(conn, node, key, bundle.id)
    assert Nodes.get_node!(node.id).active_bundle_id == bundle.id
  end

  test "a bundle from another project is ignored", %{conn: conn} do
    {node, key} = node_with_key_fixture()
    other = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture()

    heartbeat(conn, node, key, other.id)
    assert Nodes.get_node!(node.id).active_bundle_id == nil
  end

  test "a malformed bundle ID is ignored", %{conn: conn} do
    {node, key} = node_with_key_fixture()
    heartbeat(conn, node, key, "not-a-uuid")
    assert Nodes.get_node!(node.id).active_bundle_id == nil
  end
end
