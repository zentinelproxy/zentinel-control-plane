defmodule ZentinelCp.PortalTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Portal
  alias ZentinelCp.Projects.Project

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OpenApiFixtures

  describe "Project portal settings" do
    test "portal_enabled? defaults to false" do
      project = project_fixture()
      refute Project.portal_enabled?(project)
    end

    test "portal_access defaults to disabled" do
      project = project_fixture()
      assert Project.portal_access(project) == "disabled"
    end

    test "portal_title defaults to project name" do
      project = project_fixture()
      assert Project.portal_title(project) == project.name
    end

    test "portal settings work with custom values" do
      project = project_fixture()

      {:ok, project} =
        ZentinelCp.Projects.update_project(project, %{
          settings: %{
            "portal_enabled" => true,
            "portal_access" => "public",
            "portal_title" => "My API Portal",
            "portal_description" => "Custom description",
            "portal_logo_url" => "https://example.com/logo.png"
          }
        })

      assert Project.portal_enabled?(project)
      assert Project.portal_access(project) == "public"
      assert Project.portal_title(project) == "My API Portal"
      assert Project.portal_description(project) == "Custom description"
      assert Project.portal_logo_url(project) == "https://example.com/logo.png"
    end
  end

  describe "list_project_specs/1" do
    test "returns active specs for a project" do
      project = project_fixture()
      spec = openapi_spec_fixture(%{project: project})

      specs = Portal.list_project_specs(project.id)
      assert length(specs) == 1
      assert hd(specs).id == spec.id
    end

    test "returns empty list when no specs" do
      project = project_fixture()
      assert Portal.list_project_specs(project.id) == []
    end
  end

  describe "get_spec_paths/1" do
    test "extracts paths from spec data" do
      spec =
        openapi_spec_fixture(%{
          spec_data: %{
            "openapi" => "3.0.0",
            "info" => %{"title" => "Test", "version" => "1.0"},
            "paths" => %{
              "/users" => %{
                "get" => %{
                  "summary" => "List users",
                  "tags" => ["Users"],
                  "parameters" => [],
                  "responses" => %{"200" => %{"description" => "OK"}}
                },
                "post" => %{
                  "summary" => "Create user",
                  "tags" => ["Users"],
                  "parameters" => [],
                  "responses" => %{"201" => %{"description" => "Created"}}
                }
              }
            }
          }
        })

      paths = Portal.get_spec_paths(spec)
      assert length(paths) == 2

      get_endpoint = Enum.find(paths, &(&1.method == "GET"))
      assert get_endpoint.path == "/users"
      assert get_endpoint.summary == "List users"
      assert get_endpoint.tags == ["Users"]
    end

    test "returns empty list for nil spec" do
      assert Portal.get_spec_paths(nil) == []
    end
  end

  describe "get_spec_schemas/1" do
    test "extracts schemas from spec data" do
      spec =
        openapi_spec_fixture(%{
          spec_data: %{
            "openapi" => "3.0.0",
            "info" => %{"title" => "Test", "version" => "1.0"},
            "paths" => %{},
            "components" => %{
              "schemas" => %{
                "User" => %{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "integer"},
                    "name" => %{"type" => "string"}
                  }
                }
              }
            }
          }
        })

      schemas = Portal.get_spec_schemas(spec)
      assert Map.has_key?(schemas, "User")
      assert schemas["User"]["type"] == "object"
    end
  end

  describe "group_paths_by_tag/1" do
    test "groups paths by first tag" do
      paths = [
        %{path: "/users", method: "GET", tags: ["Users"]},
        %{path: "/users", method: "POST", tags: ["Users"]},
        %{path: "/items", method: "GET", tags: ["Items"]}
      ]

      grouped = Portal.group_paths_by_tag(paths)
      assert length(grouped) == 2
      tags = Enum.map(grouped, fn {tag, _} -> tag end)
      assert "Items" in tags
      assert "Users" in tags
    end

    test "untagged paths go to Other" do
      paths = [
        %{path: "/health", method: "GET", tags: []}
      ]

      grouped = Portal.group_paths_by_tag(paths)
      assert [{_, endpoints}] = grouped
      assert length(endpoints) == 1
    end
  end

  describe "build_curl_command/4" do
    test "builds basic curl command" do
      cmd = Portal.build_curl_command("GET", "https://api.example.com/users")
      assert cmd =~ "curl -X GET"
      assert cmd =~ "https://api.example.com/users"
    end

    test "includes headers" do
      cmd =
        Portal.build_curl_command("POST", "https://api.example.com/users", [
          {"Content-Type", "application/json"}
        ])

      assert cmd =~ "-H 'Content-Type: application/json'"
    end

    test "includes body" do
      cmd =
        Portal.build_curl_command(
          "POST",
          "https://api.example.com/users",
          [],
          ~s({"name": "test"})
        )

      assert cmd =~ ~s(-d '{"name": "test"}')
    end
  end

  describe "portal key self-service" do
    test "create_portal_key creates a scoped key" do
      project = project_fixture()
      user = user_fixture()

      {:ok, key} = Portal.create_portal_key(project.id, "my-key", user.id)
      assert key.name == "portal-my-key"
      assert key.project_id == project.id
      assert key.scopes == ["services:read", "bundles:read"]
    end

    test "list_portal_keys returns user's keys for a project" do
      project = project_fixture()
      user = user_fixture()

      {:ok, _} = Portal.create_portal_key(project.id, "key-1", user.id)
      {:ok, _} = Portal.create_portal_key(project.id, "key-2", user.id)

      keys = Portal.list_portal_keys(project.id, user.id)
      assert length(keys) == 2
    end

    test "revoke_portal_key revokes own key" do
      project = project_fixture()
      user = user_fixture()

      {:ok, key} = Portal.create_portal_key(project.id, "revoke-me", user.id)
      assert {:ok, _} = Portal.revoke_portal_key(key.id, user.id)

      # Should not appear in active keys list
      keys = Portal.list_portal_keys(project.id, user.id)
      assert length(keys) == 0
    end

    test "revoke_portal_key rejects other user's key" do
      project = project_fixture()
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, key} = Portal.create_portal_key(project.id, "not-yours", user1.id)
      assert {:error, :not_authorized} = Portal.revoke_portal_key(key.id, user2.id)
    end
  end
end
