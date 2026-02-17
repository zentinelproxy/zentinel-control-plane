defmodule ZentinelCpWeb.Api.PluginControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.PluginFixtures

  setup %{conn: conn} do
    project = project_fixture()
    {conn, _api_key} = authenticate_api(conn, project: project)
    %{conn: conn, project: project}
  end

  describe "GET /api/v1/projects/:slug/plugins" do
    test "lists plugins", %{conn: conn, project: project} do
      _p = plugin_fixture(%{project: project})

      conn = get(conn, ~p"/api/v1/projects/#{project.slug}/plugins")
      assert %{"plugins" => plugins, "total" => 1} = json_response(conn, 200)
      assert length(plugins) == 1
    end

    test "returns empty list for project with no plugins", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/v1/projects/#{project.slug}/plugins")
      assert %{"plugins" => [], "total" => 0} = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/projects/:slug/plugins" do
    test "creates plugin", %{conn: conn, project: project} do
      conn =
        post(conn, ~p"/api/v1/projects/#{project.slug}/plugins", %{
          "name" => "Test Plugin",
          "plugin_type" => "wasm",
          "description" => "A test"
        })

      assert %{"plugin" => plugin} = json_response(conn, 201)
      assert plugin["name"] == "Test Plugin"
      assert plugin["plugin_type"] == "wasm"
      assert plugin["slug"] == "test-plugin"
    end

    test "returns errors for invalid data", %{conn: conn, project: project} do
      conn =
        post(conn, ~p"/api/v1/projects/#{project.slug}/plugins", %{
          "plugin_type" => "invalid"
        })

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/projects/:slug/plugins/:id" do
    test "returns plugin", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})

      conn = get(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}")
      assert %{"plugin" => p} = json_response(conn, 200)
      assert p["id"] == plugin.id
    end

    test "returns 404 for unknown plugin", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "PUT /api/v1/projects/:slug/plugins/:id" do
    test "updates plugin", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})

      conn =
        put(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}", %{
          "name" => "Updated Name"
        })

      assert %{"plugin" => p} = json_response(conn, 200)
      assert p["name"] == "Updated Name"
    end
  end

  describe "DELETE /api/v1/projects/:slug/plugins/:id" do
    test "deletes plugin", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})

      conn = delete(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}")
      assert response(conn, 204)
    end
  end

  describe "GET /api/v1/projects/:slug/plugins/:id/versions" do
    test "lists versions", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})
      _v = plugin_version_fixture(%{plugin: plugin})

      conn = get(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}/versions")
      assert %{"versions" => versions, "total" => 1} = json_response(conn, 200)
      assert length(versions) == 1
    end
  end

  describe "POST /api/v1/projects/:slug/plugins/:id/versions" do
    test "uploads version", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})
      binary_b64 = Base.encode64("fake-wasm-content")

      conn =
        post(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}/versions", %{
          "version" => "1.0.0",
          "binary" => binary_b64,
          "changelog" => "First version"
        })

      assert %{"version" => v} = json_response(conn, 201)
      assert v["version"] == "1.0.0"
      assert v["checksum"] != nil
    end

    test "rejects invalid base64", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})

      conn =
        post(conn, ~p"/api/v1/projects/#{project.slug}/plugins/#{plugin.id}/versions", %{
          "version" => "1.0.0",
          "binary" => "not-base64!!!"
        })

      assert json_response(conn, 422)
    end
  end

  describe "service plugin chain" do
    test "attach and detach plugin", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})
      service = service_fixture(%{project: project})

      # Attach
      conn =
        post(conn, ~p"/api/v1/projects/#{project.slug}/services/#{service.id}/plugins", %{
          "plugin_id" => plugin.id,
          "position" => 0
        })

      assert %{"service_plugin" => sp} = json_response(conn, 201)
      assert sp["plugin_id"] == plugin.id

      # Detach
      conn =
        delete(
          conn,
          ~p"/api/v1/projects/#{project.slug}/services/#{service.id}/plugins/#{plugin.id}"
        )

      assert response(conn, 204)
    end

    test "reorder plugins", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})
      p1 = plugin_fixture(%{project: project, name: "First"})
      p2 = plugin_fixture(%{project: project, name: "Second"})

      {:ok, sp1} =
        ZentinelCp.Plugins.attach_plugin(%{service_id: service.id, plugin_id: p1.id, position: 0})

      {:ok, sp2} =
        ZentinelCp.Plugins.attach_plugin(%{service_id: service.id, plugin_id: p2.id, position: 1})

      conn =
        put(conn, ~p"/api/v1/projects/#{project.slug}/services/#{service.id}/plugins/reorder", %{
          "order" => [
            %{"id" => sp1.id, "position" => 2},
            %{"id" => sp2.id, "position" => 1}
          ]
        })

      assert %{"service_plugins" => chain} = json_response(conn, 200)
      assert hd(chain)["position"] == 1
    end
  end

  describe "GET /api/v1/marketplace/plugins" do
    test "lists public plugins", %{conn: conn} do
      {:ok, _} =
        ZentinelCp.Plugins.create_plugin(%{
          name: "Marketplace Plugin",
          plugin_type: "wasm",
          public: true
        })

      conn = get(conn, ~p"/api/v1/marketplace/plugins")
      assert %{"plugins" => plugins} = json_response(conn, 200)
      assert length(plugins) == 1
    end
  end
end
