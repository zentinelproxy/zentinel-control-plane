defmodule ZentinelCpWeb.NodesLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "NodesLive.Index" do
    test "renders nodes list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/nodes")
      assert html =~ "Nodes"
      assert html =~ "No nodes found"
    end

    test "displays nodes when they exist", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project, name: "test-proxy-1"})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/nodes")
      assert html =~ "test-proxy-1"
      assert html =~ "Unknown"
    end

    test "filters nodes by status", %{conn: conn, project: project} do
      online = node_fixture(%{project: project, name: "online-node"})
      _offline = node_fixture(%{project: project, name: "offline-node"})

      # Set node status via heartbeat
      ZentinelCp.Nodes.record_heartbeat(online, %{health: %{"status" => "healthy"}})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/nodes")

      html = view |> element("form") |> render_change(%{status: "online"})
      assert html =~ "online-node"
    end

    test "shows stats cards", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project, status: "online"})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/nodes")
      assert html =~ "Online"
      assert html =~ "Offline"
      assert html =~ "Total"
    end

    test "deletes a node", %{conn: conn, project: project} do
      node = node_fixture(%{project: project, name: "deletable-node"})
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/nodes")

      view
      |> element(~s|button[phx-click=delete][phx-value-id="#{node.id}"]|)
      |> render_click()

      refute render(view) =~ "deletable-node"
    end
  end
end
