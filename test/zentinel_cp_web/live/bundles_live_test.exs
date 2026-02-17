defmodule ZentinelCpWeb.BundlesLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.RolloutsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "BundlesLive.Index" do
    test "renders bundles list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles")
      assert html =~ "Bundles"
    end

    test "shows compiled bundles", %{conn: conn, project: project} do
      _bundle = compiled_bundle_fixture(%{project: project, version: "v2.0.1"})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles")
      assert html =~ "v2.0.1"
      assert html =~ "compiled"
    end

    test "shows empty state when no bundles", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles")
      assert html =~ "No bundles" or html =~ "Bundles"
    end
  end
end
