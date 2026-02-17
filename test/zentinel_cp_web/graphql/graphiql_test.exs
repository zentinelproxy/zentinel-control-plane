defmodule ZentinelCpWeb.GraphQL.GraphiQLTest do
  use ZentinelCpWeb.ConnCase, async: true

  describe "GET /dev/graphiql" do
    @tag :skip
    # GraphiQL is only mounted when dev_routes is enabled (dev environment).
    # This test verifies the route exists and serves the playground.
    # Run manually with: MIX_ENV=dev mix test --include skip
    test "serves the GraphiQL playground", %{conn: conn} do
      conn = get(conn, "/dev/graphiql")
      assert html_response(conn, 200) =~ "graphiql"
    end

    test "graphiql route is configured in dev_routes block" do
      # Verify the route is defined in the router (compile-time gated by dev_routes)
      # This ensures we haven't accidentally removed it
      source = File.read!("lib/zentinel_cp_web/router.ex")
      assert source =~ "forward \"/graphiql\", Absinthe.Plug.GraphiQL"
    end
  end
end
