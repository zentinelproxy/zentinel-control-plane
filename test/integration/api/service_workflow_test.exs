defmodule ZentinelCpWeb.Integration.Api.ServiceWorkflowTest do
  @moduledoc """
  Integration tests for service API workflows.

  Tests the complete lifecycle: create → list → show → update → delete,
  as well as KDL preview, reorder, and bundle generation.
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "service CRUD workflow" do
    test "create → list → show → update → delete", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Step 1: Create service
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/services", %{
          name: "My API",
          route_path: "/api/*",
          upstream_url: "http://localhost:3000"
        })
        |> json_response!(201)

      assert create_resp["service"]["id"]
      assert create_resp["service"]["name"] == "My API"
      assert create_resp["service"]["route_path"] == "/api/*"
      assert create_resp["service"]["upstream_url"] == "http://localhost:3000"
      assert create_resp["service"]["slug"] == "my-api"
      assert create_resp["service"]["enabled"] == true

      service_id = create_resp["service"]["id"]

      # Step 2: List services
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/services")
        |> json_response!(200)

      assert list_resp["total"] >= 1
      assert Enum.find(list_resp["services"], &(&1["id"] == service_id))

      # Step 3: Show service
      show_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/services/#{service_id}")
        |> json_response!(200)

      assert show_resp["service"]["id"] == service_id
      assert show_resp["service"]["name"] == "My API"

      # Step 4: Update service
      update_resp =
        api_conn
        |> put("/api/v1/projects/#{project_slug}/services/#{service_id}", %{
          name: "My Updated API",
          timeout_seconds: 60
        })
        |> json_response!(200)

      assert update_resp["service"]["name"] == "My Updated API"
      assert update_resp["service"]["timeout_seconds"] == 60

      # Step 5: Delete service
      api_conn
      |> delete("/api/v1/projects/#{project_slug}/services/#{service_id}")
      |> response(204)

      # Verify deleted
      api_conn
      |> get("/api/v1/projects/#{project_slug}/services/#{service_id}")
      |> json_response!(404)
    end

    test "filter by enabled", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create enabled service
      api_conn
      |> post("/api/v1/projects/#{project_slug}/services", %{
        name: "Enabled Service",
        route_path: "/enabled/*",
        upstream_url: "http://localhost:3001"
      })
      |> json_response!(201)

      # Create disabled service
      api_conn
      |> post("/api/v1/projects/#{project_slug}/services", %{
        name: "Disabled Service",
        route_path: "/disabled/*",
        upstream_url: "http://localhost:3002",
        enabled: false
      })
      |> json_response!(201)

      # Filter enabled only
      enabled_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/services?enabled=true")
        |> json_response!(200)

      assert Enum.all?(enabled_resp["services"], &(&1["enabled"] == true))
      assert enabled_resp["total"] == 1
    end
  end

  describe "preview KDL" do
    test "preview generated KDL", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create a service first
      api_conn
      |> post("/api/v1/projects/#{project_slug}/services", %{
        name: "API Service",
        route_path: "/api/*",
        upstream_url: "http://localhost:3000"
      })
      |> json_response!(201)

      # Preview KDL
      preview_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/services/preview-kdl")
        |> json_response!(200)

      assert preview_resp["kdl"]
      assert preview_resp["kdl"] =~ "/api/*"
      assert preview_resp["kdl"] =~ "http://localhost:3000"
    end

    test "preview KDL with no services returns error", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:read"])

      error_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/services/preview-kdl")
        |> json_response!(422)

      assert error_resp["error"] =~ "No enabled services"
    end
  end

  describe "reorder services" do
    test "reorder updates positions", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create 3 services
      ids =
        for i <- 1..3 do
          resp =
            api_conn
            |> post("/api/v1/projects/#{project_slug}/services", %{
              name: "Service #{i}",
              route_path: "/svc#{i}/*",
              upstream_url: "http://localhost:#{3000 + i}"
            })
            |> json_response!(201)

          resp["service"]["id"]
        end

      # Reverse the order
      reversed = Enum.reverse(ids)

      reorder_resp =
        api_conn
        |> put("/api/v1/projects/#{project_slug}/services/reorder", %{
          service_ids: reversed
        })
        |> json_response!(200)

      assert reorder_resp["ok"] == true

      # Verify new order
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/services")
        |> json_response!(200)

      listed_ids = Enum.map(list_resp["services"], & &1["id"])
      assert listed_ids == reversed
    end
  end

  describe "generate bundle from services" do
    test "generates a bundle", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn,
          scopes: ["services:read", "services:write", "bundles:read"]
        )

      project_slug = context.project.slug

      # Create a service
      api_conn
      |> post("/api/v1/projects/#{project_slug}/services", %{
        name: "Bundle Service",
        route_path: "/api/*",
        upstream_url: "http://localhost:3000"
      })
      |> json_response!(201)

      # Generate bundle
      bundle_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/services/generate-bundle", %{
          version: "svc-1.0.0"
        })
        |> json_response!(201)

      assert bundle_resp["bundle"]["id"]
      assert bundle_resp["bundle"]["version"] == "svc-1.0.0"
      assert bundle_resp["bundle"]["project_id"] == context.project.id
    end

    test "generate bundle without services returns error", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services/generate-bundle", %{
          version: "1.0.0"
        })
        |> json_response!(422)

      assert error_resp["error"] =~ "No enabled services"
    end

    test "generate bundle without version returns error", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services/generate-bundle", %{})
        |> json_response!(422)

      assert error_resp["error"] =~ "version is required"
    end
  end

  describe "validation errors" do
    test "missing required fields", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services", %{})
        |> json_response!(422)

      assert error_resp["error"]["name"]
      assert error_resp["error"]["route_path"]
    end

    test "invalid route_path", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services", %{
          name: "Bad Route",
          route_path: "no-leading-slash",
          upstream_url: "http://localhost:3000"
        })
        |> json_response!(422)

      assert error_resp["error"]["route_path"]
    end

    test "must set either upstream_url, respond_status, or redirect_url", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services", %{
          name: "No Backend",
          route_path: "/test/*"
        })
        |> json_response!(422)

      assert error_resp["error"]["upstream_url"]
    end
  end

  describe "scope enforcement" do
    test "read-only key cannot create services", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:read"])

      api_conn
      |> post("/api/v1/projects/#{context.project.slug}/services", %{
        name: "Forbidden",
        route_path: "/test/*",
        upstream_url: "http://localhost:3000"
      })
      |> json_response!(403)
    end

    test "write-only key cannot list services", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["services:write"])

      api_conn
      |> get("/api/v1/projects/#{context.project.slug}/services")
      |> json_response!(403)
    end
  end

  describe "project scoping" do
    test "cannot access services from another project", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      # Create a service in our project
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/services", %{
          name: "My Service",
          route_path: "/api/*",
          upstream_url: "http://localhost:3000"
        })
        |> json_response!(201)

      service_id = create_resp["service"]["id"]

      # Create a different project
      other_org = ZentinelCp.OrgsFixtures.org_fixture(%{name: "Other Org"})
      other_project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: other_org})

      # Try to access the service via the other project's slug
      api_conn
      |> get("/api/v1/projects/#{other_project.slug}/services/#{service_id}")
      |> json_response!(404)
    end
  end
end
