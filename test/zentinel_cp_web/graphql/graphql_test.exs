defmodule ZentinelCpWeb.GraphQL.GraphQLTest do
  use ZentinelCpWeb.ConnCase, async: true

  alias ZentinelCp.NodesFixtures
  alias ZentinelCp.ProjectsFixtures
  alias ZentinelCp.RolloutsFixtures

  describe "queries" do
    test "fetch project by slug", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query($slug: String!) {
        project(slug: $slug) {
          id
          name
          slug
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query, variables: %{slug: project.slug}})
        |> json_response(200)

      assert resp["data"]["project"]["slug"] == project.slug
      assert resp["data"]["project"]["name"] == project.name
    end

    test "list nodes for project", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      node = NodesFixtures.node_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query($projectId: ID!) {
        nodes(projectId: $projectId) {
          id
          hostname
          status
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query, variables: %{projectId: project.id}})
        |> json_response(200)

      assert [returned_node] = resp["data"]["nodes"]
      assert returned_node["id"] == node.id
    end

    test "list bundles with limit", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      bundle = RolloutsFixtures.compiled_bundle_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query($projectId: ID!, $limit: Int) {
        bundles(projectId: $projectId, limit: $limit) {
          id
          version
          status
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{
          query: query,
          variables: %{projectId: project.id, limit: 1}
        })
        |> json_response(200)

      assert [returned_bundle] = resp["data"]["bundles"]
      assert returned_bundle["id"] == bundle.id
    end

    test "nested project query with nodes and bundles", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      NodesFixtures.node_fixture(%{project: project})
      RolloutsFixtures.compiled_bundle_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query($slug: String!) {
        project(slug: $slug) {
          name
          nodes { id status }
          bundles(limit: 5) { id version }
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query, variables: %{slug: project.slug}})
        |> json_response(200)

      project_data = resp["data"]["project"]
      assert [_] = project_data["nodes"]
      assert [_ | _] = project_data["bundles"]
    end
  end

  describe "mutations" do
    test "create rollout", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      bundle = RolloutsFixtures.compiled_bundle_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      mutation = """
      mutation($input: CreateRolloutInput!) {
        createRollout(input: $input) {
          id
          state
          strategy
        }
      }
      """

      variables = %{
        input: %{
          projectId: project.id,
          bundleId: bundle.id,
          strategy: "rolling",
          targetSelector: Jason.encode!(%{"type" => "all"})
        }
      }

      resp =
        conn
        |> post("/api/v1/graphql", %{query: mutation, variables: variables})
        |> json_response(200)

      assert resp["data"]["createRollout"]["state"] == "pending"
      assert resp["data"]["createRollout"]["strategy"] == "rolling"
    end

    test "pause rollout", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      rollout = RolloutsFixtures.rollout_fixture(%{project: project})

      # Transition to running so it can be paused
      {:ok, rollout} =
        rollout
        |> Ecto.Changeset.change(state: "running")
        |> ZentinelCp.Repo.update()

      {conn, _api_key} = authenticate_api(conn, project: project)

      mutation = """
      mutation($id: ID!) {
        pauseRollout(id: $id) {
          id
          state
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: mutation, variables: %{id: rollout.id}})
        |> json_response(200)

      assert resp["data"]["pauseRollout"]["state"] == "paused"
    end
  end

  describe "auth" do
    test "rejects request without auth", %{conn: conn} do
      query = """
      query { projects { id } }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(401)

      assert resp["error"] || resp["errors"]
    end

    test "rejects insufficient scope", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()

      {conn, _api_key} =
        authenticate_api(conn, project: project, scopes: ["nodes:read"])

      query = """
      query($projectId: ID!) {
        bundles(projectId: $projectId) {
          id
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query, variables: %{projectId: project.id}})
        |> json_response(200)

      assert [error] = resp["errors"]
      assert error["message"] =~ "Insufficient scope"
    end

    test "allows matching scope", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      NodesFixtures.node_fixture(%{project: project})

      {conn, _api_key} =
        authenticate_api(conn, project: project, scopes: ["nodes:read"])

      query = """
      query($projectId: ID!) {
        nodes(projectId: $projectId) {
          id
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query, variables: %{projectId: project.id}})
        |> json_response(200)

      assert is_list(resp["data"]["nodes"])
      refute resp["errors"]
    end
  end

  describe "errors" do
    test "not-found returns GraphQL error", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query {
        project(slug: "nonexistent-project-slug") {
          id
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(200)

      assert [error] = resp["errors"]
      assert error["message"] =~ "not found"
    end
  end
end
