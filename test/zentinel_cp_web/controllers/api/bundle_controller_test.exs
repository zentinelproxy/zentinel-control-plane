defmodule ZentinelCpWeb.Api.BundleControllerTest do
  use ZentinelCpWeb.ConnCase

  alias ZentinelCp.Bundles

  import ZentinelCp.ProjectsFixtures

  @valid_kdl """
  system {
    workers 4
  }
  listeners {
    listener "http" address="0.0.0.0:8080"
  }
  """

  defp create_compiled_bundle(project) do
    {:ok, bundle} =
      Bundles.create_bundle(%{
        project_id: project.id,
        version: "1.0.#{System.unique_integer([:positive])}",
        config_source: @valid_kdl
      })

    {:ok, compiled} = Bundles.update_status(bundle, "compiled")
    compiled
  end

  describe "POST /api/v1/projects/:project_slug/bundles/:id/revoke" do
    test "revokes a compiled bundle", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      bundle = create_compiled_bundle(project)

      conn = post(conn, "/api/v1/projects/#{project.slug}/bundles/#{bundle.id}/revoke")

      assert %{"bundle" => %{"status" => "revoked"}} = json_response(conn, 200)
    end

    test "returns 409 for non-compiled bundle", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      {:ok, bundle} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      # Bundle is pending/failed, not compiled
      conn = post(conn, "/api/v1/projects/#{project.slug}/bundles/#{bundle.id}/revoke")

      assert json_response(conn, 409)["error"] =~ "Only compiled"
    end
  end

  describe "download revoked bundle" do
    test "returns 409 for revoked bundle", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      bundle = create_compiled_bundle(project)

      {:ok, _revoked} = Bundles.revoke_bundle(bundle)

      conn = get(conn, "/api/v1/projects/#{project.slug}/bundles/#{bundle.id}/download")

      assert json_response(conn, 409)["error"] =~ "revoked"
    end
  end

  describe "assign revoked bundle" do
    test "returns 409 for revoked bundle", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      bundle = create_compiled_bundle(project)

      {:ok, _revoked} = Bundles.revoke_bundle(bundle)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/bundles/#{bundle.id}/assign", %{
          node_ids: []
        })

      assert json_response(conn, 409)["error"] =~ "revoked"
    end
  end
end
