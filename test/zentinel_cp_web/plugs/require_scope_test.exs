defmodule ZentinelCpWeb.Plugs.RequireScopeTest do
  use ZentinelCpWeb.ConnCase

  alias ZentinelCpWeb.Plugs.RequireScope
  alias ZentinelCp.AccountsFixtures
  alias ZentinelCp.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    user = AccountsFixtures.user_fixture()
    %{project: project, user: user}
  end

  describe "scope enforcement" do
    test "allows request when key has required scope", %{conn: conn, project: project, user: user} do
      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project, scopes: ["bundles:read"])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => project.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:read"))

      refute conn.halted
    end

    test "allows request when key has empty scopes (legacy full access)", %{
      conn: conn,
      project: project,
      user: user
    } do
      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project, scopes: [])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => project.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:write"))

      refute conn.halted
    end

    test "rejects request when key lacks required scope", %{
      conn: conn,
      project: project,
      user: user
    } do
      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project, scopes: ["nodes:read"])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => project.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:write"))

      assert conn.halted
      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["error"] =~ "Insufficient scope"
    end
  end

  describe "project enforcement" do
    test "allows request when key project matches request project", %{
      conn: conn,
      project: project,
      user: user
    } do
      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project, scopes: ["bundles:read"])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => project.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:read"))

      refute conn.halted
      assert conn.assigns[:current_project].id == project.id
    end

    test "rejects request when key project differs from request project", %{
      conn: conn,
      user: user
    } do
      project_a = ProjectsFixtures.project_fixture(%{name: "Project A"})
      project_b = ProjectsFixtures.project_fixture(%{name: "Project B"})

      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project_a, scopes: ["bundles:read"])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => project_b.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:read"))

      assert conn.halted
      assert conn.status == 404
    end

    test "allows key without project_id to access any project", %{conn: conn, user: user} do
      project = ProjectsFixtures.project_fixture(%{name: "Any Project"})

      {:ok, api_key} =
        ZentinelCp.Accounts.create_api_key(%{
          name: "global-key",
          user_id: user.id,
          project_id: nil,
          scopes: ["bundles:read"]
        })

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{api_key.key}")
        |> Plug.Conn.assign(:current_api_key, api_key)
        |> Map.put(:params, %{"project_slug" => project.slug})
        |> RequireScope.call(RequireScope.init(scope: "bundles:read"))

      refute conn.halted
      assert conn.assigns[:current_project].id == project.id
    end

    test "returns 404 when project slug does not exist", %{
      conn: conn,
      project: project,
      user: user
    } do
      {conn, _api_key} =
        authenticate_api(conn, user: user, project: project, scopes: ["bundles:read"])

      conn =
        conn
        |> Map.put(:params, %{"project_slug" => "nonexistent-project"})
        |> RequireScope.call(RequireScope.init(scope: "bundles:read"))

      assert conn.halted
      assert conn.status == 404
    end
  end
end
