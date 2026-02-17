defmodule ZentinelCpWeb.BundlesLive.HistoryTest do
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

  describe "BundlesLive.History" do
    test "renders version history timeline", %{conn: conn, project: project} do
      _b1 = compiled_bundle_fixture(%{project: project, version: "v1.0.0"})
      _b2 = compiled_bundle_fixture(%{project: project, version: "v1.1.0"})
      _b3 = compiled_bundle_fixture(%{project: project, version: "v1.2.0"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles/history")

      assert html =~ "Version History"
      assert html =~ "v1.0.0"
      assert html =~ "v1.1.0"
      assert html =~ "v1.2.0"
      assert html =~ "version-timeline"
    end

    test "shows diff stats between versions", %{conn: conn, project: project} do
      _b1 =
        compiled_bundle_fixture(%{
          project: project,
          version: "v1.0.0",
          config_source: "system { workers 2 }"
        })

      _b2 =
        compiled_bundle_fixture(%{
          project: project,
          version: "v2.0.0",
          config_source: "system { workers 4 }\nlisteners { }"
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles/history")

      assert html =~ "diff-stats"
    end

    test "expand_diff shows inline diff", %{conn: conn, project: project} do
      _b1 =
        compiled_bundle_fixture(%{
          project: project,
          version: "v1.0.0",
          config_source: "system { workers 2 }"
        })

      _b2 =
        compiled_bundle_fixture(%{
          project: project,
          version: "v2.0.0",
          config_source: "system { workers 4 }"
        })

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/bundles/history")

      # Find the first expand-diff button's bundle ID (the newer bundle with a diff)
      assert html =~ "expand-diff"

      # The first bundle in the timeline (newest) has the diff — click it
      [bundle_id] =
        Regex.scan(~r/phx-value-id="([^"]+)"[^>]*data-testid="expand-diff"/, html)
        |> List.first()
        |> tl()

      html = render_click(view, "expand_diff", %{"id" => bundle_id})
      assert html =~ "inline-diff"
    end

    test "links to bundle show page", %{conn: conn, project: project} do
      b1 = compiled_bundle_fixture(%{project: project, version: "v1.0.0"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles/history")

      assert html =~ "/projects/#{project.slug}/bundles/#{b1.id}"
    end

    test "shows empty state when no bundles", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/bundles/history")

      assert html =~ "No bundle versions yet"
    end
  end
end
