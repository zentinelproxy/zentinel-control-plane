defmodule ZentinelCpWeb.Integration.Api.UpstreamGroupWorkflowTest do
  @moduledoc """
  Integration tests for upstream group API workflows.
  """
  use ZentinelCpWeb.IntegrationCase

  @moduletag :integration

  describe "upstream group CRUD workflow" do
    test "create → list → show → update → delete", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/upstream-groups", %{
          name: "API Backends",
          algorithm: "round_robin"
        })
        |> json_response!(201)

      assert create_resp["upstream_group"]["id"]
      assert create_resp["upstream_group"]["name"] == "API Backends"
      assert create_resp["upstream_group"]["slug"] == "api-backends"
      assert create_resp["upstream_group"]["algorithm"] == "round_robin"

      group_id = create_resp["upstream_group"]["id"]

      # List
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/upstream-groups")
        |> json_response!(200)

      assert list_resp["total"] >= 1

      # Show
      show_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}")
        |> json_response!(200)

      assert show_resp["upstream_group"]["id"] == group_id

      # Update
      update_resp =
        api_conn
        |> put("/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}", %{
          name: "Updated Backends",
          algorithm: "least_conn"
        })
        |> json_response!(200)

      assert update_resp["upstream_group"]["name"] == "Updated Backends"
      assert update_resp["upstream_group"]["algorithm"] == "least_conn"

      # Delete
      api_conn
      |> delete("/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}")
      |> response(204)
    end
  end

  describe "upstream target management" do
    test "add and remove targets", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create group
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/upstream-groups", %{
          name: "LB Group",
          algorithm: "round_robin"
        })
        |> json_response!(201)

      group_id = create_resp["upstream_group"]["id"]

      # Add target
      target_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}/targets", %{
          host: "api1.internal",
          port: 8080,
          weight: 100
        })
        |> json_response!(201)

      assert target_resp["target"]["host"] == "api1.internal"
      assert target_resp["target"]["port"] == 8080

      target_id = target_resp["target"]["id"]

      # Update target
      update_resp =
        api_conn
        |> put(
          "/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}/targets/#{target_id}",
          %{
            weight: 200
          }
        )
        |> json_response!(200)

      assert update_resp["target"]["weight"] == 200

      # Delete target
      api_conn
      |> delete(
        "/api/v1/projects/#{project_slug}/upstream-groups/#{group_id}/targets/#{target_id}"
      )
      |> response(204)
    end
  end
end
