defmodule ZentinelCpWeb.GraphQL.SubscriptionTest do
  use ZentinelCpWeb.ConnCase, async: true

  alias ZentinelCp.ProjectsFixtures
  alias ZentinelCp.RolloutsFixtures
  alias ZentinelCp.NodesFixtures

  describe "rollout_progress subscription" do
    test "publishes rollout updates", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      rollout = RolloutsFixtures.rollout_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      # Verify the subscription field is queryable via introspection
      query = """
      query {
        __type(name: "RootSubscriptionType") {
          fields {
            name
          }
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(200)

      field_names =
        resp["data"]["__type"]["fields"]
        |> Enum.map(& &1["name"])

      assert "rolloutProgress" in field_names

      # Verify publish doesn't error
      Absinthe.Subscription.publish(
        ZentinelCpWeb.Endpoint,
        rollout,
        rollout_progress: rollout.id
      )
    end
  end

  describe "node_status subscription" do
    test "publishes node updates", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      node = NodesFixtures.node_fixture(%{project: project})
      {conn, _api_key} = authenticate_api(conn, project: project)

      # Verify the subscription field is queryable via introspection
      query = """
      query {
        __type(name: "RootSubscriptionType") {
          fields {
            name
          }
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(200)

      field_names =
        resp["data"]["__type"]["fields"]
        |> Enum.map(& &1["name"])

      assert "nodeStatus" in field_names

      # Verify publish doesn't error
      Absinthe.Subscription.publish(
        ZentinelCpWeb.Endpoint,
        node,
        node_status: node.project_id
      )
    end
  end

  describe "alert_state subscription" do
    test "is available in the schema", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      query = """
      query {
        __type(name: "RootSubscriptionType") {
          fields {
            name
            args {
              name
              type { name kind ofType { name } }
            }
          }
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(200)

      fields = resp["data"]["__type"]["fields"]
      alert_field = Enum.find(fields, &(&1["name"] == "alertState"))
      assert alert_field

      arg = hd(alert_field["args"])
      assert arg["name"] == "projectId"
    end
  end

  describe "authentication" do
    test "unauthenticated requests are rejected", %{conn: conn} do
      query = """
      query {
        __type(name: "RootSubscriptionType") {
          fields { name }
        }
      }
      """

      resp =
        conn
        |> post("/api/v1/graphql", %{query: query})
        |> json_response(401)

      assert resp["error"]
    end
  end
end
