defmodule ZentinelCpWeb.Security.ApiAccessTest do
  use ZentinelCpWeb.ConnCase, async: false

  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OrgsFixtures
  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.{Access, Accounts, Orgs, Services}

  defp api_conn(conn, user, attrs \\ %{}) do
    {:ok, key} =
      Accounts.create_api_key(Map.merge(%{name: "k", user_id: user.id, scopes: []}, attrs))

    {put_req_header(conn, "authorization", "Bearer #{key.key}"), key}
  end

  defp graphql(conn, query) do
    conn |> post("/api/v1/graphql", %{query: query}) |> json_response(200)
  end

  setup do
    org = org_fixture()
    project = project_fixture(%{org: org})
    other_project = project_fixture()
    {:ok, org: org, project: project, other_project: other_project}
  end

  describe "REST" do
    test "a key owned by a non-member cannot reach the project", %{conn: conn, project: project} do
      {conn, _} = api_conn(conn, user_fixture())
      assert conn |> get("/api/v1/projects/#{project.slug}/nodes") |> json_response(404)
    end

    test "a member's unscoped key reaches their org only", ctx do
      user = user_fixture()
      {:ok, _} = Orgs.add_member(ctx.org, user, "operator")
      {conn, _} = api_conn(ctx.conn, user)

      assert conn |> get("/api/v1/projects/#{ctx.project.slug}/nodes") |> json_response(200)
      assert conn |> get("/api/v1/projects/#{ctx.other_project.slug}/nodes") |> json_response(404)
    end

    test "removing a member disables their key", ctx do
      user = user_fixture()
      {:ok, _} = Orgs.add_member(ctx.org, user, "operator")
      {conn, _} = api_conn(ctx.conn, user)
      Orgs.remove_member(ctx.org, user)

      assert conn |> get("/api/v1/projects/#{ctx.project.slug}/nodes") |> json_response(404)
    end

    test "a reader's key cannot use a write scope", %{org: org, project: project} do
      user = user_fixture()
      {:ok, _} = Orgs.add_member(org, user, "reader")
      {:ok, key} = Accounts.create_api_key(%{name: "k", user_id: user.id, scopes: []})

      assert Access.api_key_allowed?(key, project, "nodes:read")
      refute Access.api_key_allowed?(key, project, "nodes:write")
    end

    test "a project key cannot export another project via a parameter", ctx do
      {conn, _} = api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id})

      body =
        conn
        |> get("/api/v1/projects/#{ctx.project.slug}/config/export", %{
          project_id: ctx.other_project.id
        })
        |> response(200)

      refute body =~ ctx.other_project.id
    end

    test "a scoped key cannot create a broader key", ctx do
      {conn, _} =
        api_conn(ctx.conn, admin_fixture(), %{
          project_id: ctx.project.id,
          scopes: ["api_keys:admin"]
        })

      assert conn
             |> post("/api/v1/api-keys", %{name: "x", scopes: ["nodes:write"]})
             |> json_response(403)

      assert conn |> post("/api/v1/api-keys", %{name: "x", scopes: []}) |> json_response(403)

      created =
        conn
        |> post("/api/v1/api-keys", %{
          name: "x",
          scopes: ["api_keys:admin"],
          project_id: ctx.other_project.id
        })
        |> json_response(201)

      assert created["project_id"] == ctx.project.id
    end

    test "another project's upstream target cannot be changed", ctx do
      {:ok, own_group} =
        Services.create_upstream_group(%{name: "own", project_id: ctx.project.id})

      {:ok, other_group} =
        Services.create_upstream_group(%{name: "other", project_id: ctx.other_project.id})

      {:ok, target} =
        Services.add_upstream_target(%{
          upstream_group_id: other_group.id,
          host: "10.0.0.1",
          port: 80
        })

      {conn, _} = api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id})

      path =
        "/api/v1/projects/#{ctx.project.slug}/upstream-groups/#{own_group.id}/targets/#{target.id}"

      assert conn |> put(path, %{host: "evil.example"}) |> json_response(404)
      assert Services.get_upstream_target(target.id).host == "10.0.0.1"
    end

    test "audit verification needs a global admin key", ctx do
      {member_conn, _} = api_conn(ctx.conn, user_fixture())
      assert member_conn |> get("/api/v1/audit/verify") |> json_response(403)

      {admin_conn, _} = api_conn(ctx.conn, admin_fixture())
      assert admin_conn |> get("/api/v1/audit/verify") |> json_response(200)

      {project_conn, _} = api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id})
      assert project_conn |> get("/api/v1/audit/verify") |> json_response(403)
    end
  end

  describe "GraphQL" do
    test "a project key sees only its project", ctx do
      {conn, _} = api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id})

      assert %{"data" => %{"projects" => [%{"id" => id}]}} =
               graphql(conn, "{ projects { id } }")

      assert id == ctx.project.id
    end

    test "a non-member's key sees no projects", ctx do
      {conn, _} = api_conn(ctx.conn, user_fixture())
      assert %{"data" => %{"projects" => []}} = graphql(conn, "{ projects { id } }")
    end

    test "a key cannot query another project's data", ctx do
      {conn, _} = api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id})

      assert %{"errors" => [%{"message" => "Not found"} | _]} =
               graphql(conn, ~s|{ nodes(projectId: "#{ctx.other_project.id}") { id } }|)

      assert %{"errors" => [_ | _]} =
               graphql(conn, ~s|{ project(id: "#{ctx.other_project.id}") { id } }|)
    end

    test "nested collections need their own scope", ctx do
      {conn, _} =
        api_conn(ctx.conn, admin_fixture(), %{
          project_id: ctx.project.id,
          scopes: ["services:read"]
        })

      assert %{"errors" => [%{"message" => "Insufficient scope. Required: nodes:read"} | _]} =
               graphql(conn, ~s|{ project(id: "#{ctx.project.id}") { nodes { id } } }|)
    end

    test "blue-green mutations need write scope", ctx do
      {conn, _} =
        api_conn(ctx.conn, admin_fixture(), %{project_id: ctx.project.id, scopes: ["nodes:read"]})

      query = ~s|mutation { swapBlueGreenSlot(id: "#{Ecto.UUID.generate()}") { id } }|

      assert %{"errors" => [%{"message" => "Insufficient scope. Required: rollouts:write"} | _]} =
               graphql(conn, query)
    end
  end

  describe "tenants" do
    test "project slugs are unique across orgs", %{project: project} do
      other_org = org_fixture()

      assert {:error, changeset} =
               ZentinelCp.Projects.create_project(%{
                 name: project.name,
                 slug: project.slug,
                 org_id: other_org.id
               })

      assert ZentinelCp.DataCase.errors_on(changeset)[:slug]
    end

    test "a rollout cannot use another project's bundle", %{
      project: project,
      other_project: other_project
    } do
      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: other_project})

      assert {:error, :bundle_not_found} =
               ZentinelCp.Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"},
                 strategy: "rolling"
               })
    end
  end
end

defmodule ZentinelCpWeb.Security.NodeRegistrationTest do
  use ZentinelCpWeb.ConnCase, async: false

  alias ZentinelCp.Projects

  setup do
    Application.put_env(:zentinel_cp, :require_node_registration_token, true)
    on_exit(fn -> Application.put_env(:zentinel_cp, :require_node_registration_token, false) end)
    {:ok, project: ZentinelCp.ProjectsFixtures.project_fixture()}
  end

  defp register(conn, project, token \\ nil) do
    conn = if token, do: put_req_header(conn, "x-registration-token", token), else: conn
    post(conn, "/api/v1/projects/#{project.slug}/nodes/register", %{name: "proxy-1"})
  end

  test "registration without a token is refused", %{conn: conn, project: project} do
    assert conn |> register(project) |> json_response(401)
  end

  test "a project with no token accepts none", %{conn: conn, project: project} do
    assert conn |> register(project, "guess") |> json_response(401)
  end

  test "the current token registers a node", %{conn: conn, project: project} do
    {:ok, token, project} = Projects.rotate_node_registration_token(project)
    assert %{"node_key" => _} = conn |> register(project, token) |> json_response(201)
    refute project.node_registration_token_hash == token
  end

  test "a replaced token stops working", %{conn: conn, project: project} do
    {:ok, old, project} = Projects.rotate_node_registration_token(project)
    {:ok, _new, project} = Projects.rotate_node_registration_token(project)
    assert conn |> register(project, old) |> json_response(401)
  end

  test "an API key can create a token", %{conn: conn, project: project} do
    {conn, _key} = authenticate_api(conn, project: project, scopes: ["nodes:write"])

    assert %{"registration_token" => "zcp_nrt_" <> _} =
             conn
             |> post("/api/v1/projects/#{project.slug}/nodes/registration-token")
             |> json_response(201)
  end
end
