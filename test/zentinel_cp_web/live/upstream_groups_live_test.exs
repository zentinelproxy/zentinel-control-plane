defmodule ZentinelCpWeb.UpstreamGroupsLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.UpstreamGroupFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "UpstreamGroupsLive.Index" do
    test "renders upstream groups list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/upstream-groups")
      assert html =~ "Upstream Groups"
    end

    test "shows groups", %{conn: conn, project: project} do
      _group = upstream_group_fixture(%{project: project, name: "my-test-group"})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/upstream-groups")
      assert html =~ "my-test-group"
    end

    test "shows empty state when no groups", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/upstream-groups")
      assert html =~ "No upstream groups yet"
    end
  end

  describe "UpstreamGroupsLive.New" do
    test "renders new group form", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/upstream-groups/new")
      assert html =~ "Create Upstream Group"
    end

    test "creates a group", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/upstream-groups/new")

      view
      |> form("form", %{"name" => "New Group", "algorithm" => "round_robin"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/upstream-groups/"
    end
  end

  describe "UpstreamGroupsLive.Show" do
    test "renders group detail page", %{conn: conn, project: project} do
      group = upstream_group_fixture(%{project: project, name: "Detail Group"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/upstream-groups/#{group.id}")

      assert html =~ "Detail Group"
      assert html =~ group.algorithm
    end

    test "add and remove targets", %{conn: conn, project: project} do
      group = upstream_group_fixture(%{project: project})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.slug}/upstream-groups/#{group.id}")

      # Add a target
      view
      |> form("form", %{"host" => "api.internal", "port" => "8080", "weight" => "100"})
      |> render_submit()

      html = render(view)
      assert html =~ "api.internal"
    end
  end

  describe "UpstreamGroupsLive.Edit" do
    test "renders edit form", %{conn: conn, project: project} do
      group = upstream_group_fixture(%{project: project, name: "Edit Me"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/upstream-groups/#{group.id}/edit")

      assert html =~ "Edit Upstream Group"
      assert html =~ "Edit Me"
    end

    test "updates a group", %{conn: conn, project: project} do
      group = upstream_group_fixture(%{project: project})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.slug}/upstream-groups/#{group.id}/edit")

      view
      |> form("form", %{"name" => "Updated Name", "algorithm" => "least_conn"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/upstream-groups/"
    end
  end
end
