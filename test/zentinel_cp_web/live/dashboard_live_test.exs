defmodule ZentinelCpWeb.DashboardLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OrgsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    org = org_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, org: org}
  end

  describe "DashboardLive.Index" do
    test "renders dashboard page", %{conn: conn, org: org} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ "Dashboard"
      assert html =~ "Projects"
    end

    test "displays fleet stats", %{conn: conn, org: org} do
      project = project_fixture(%{org: org})
      online_node = node_fixture(%{project: project})
      _offline_node = node_fixture(%{project: project})

      # Mark first node as online via heartbeat
      ZentinelCp.Nodes.record_heartbeat(online_node, %{health: %{"status" => "healthy"}})

      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ "Nodes Online"
      assert html =~ "Nodes Offline"
    end

    test "shows no projects message when empty", %{conn: conn, org: org} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ "No projects yet"
    end

    test "shows projects when they exist", %{conn: conn, org: org} do
      project = project_fixture(%{org: org})
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/dashboard")
      assert html =~ project.name
    end

    test "redirects for unknown org", %{conn: conn} do
      assert {:error, {:live_redirect, _}} = live(conn, ~p"/orgs/nonexistent/dashboard")
    end
  end
end
