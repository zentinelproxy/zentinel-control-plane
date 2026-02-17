defmodule ZentinelCpWeb.DriftLiveTest do
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

  describe "DriftLive.Index" do
    test "renders drift events page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "Drift Events"
      assert html =~ "No drift events found"
    end

    test "displays drift events when they exist", %{conn: conn, project: project} do
      node = node_fixture(%{project: project, name: "drifted-node"})
      _event = drift_event_fixture(%{node: node, project: project})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "drifted-node"
      assert html =~ "Active"
    end

    test "shows stats strip with counts", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      _event = drift_event_fixture(%{node: node, project: project})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "Active Drifts"
      assert html =~ "Resolved"
      assert html =~ "Managed Nodes"
    end

    test "filters by active status", %{conn: conn, project: project} do
      node1 = node_fixture(%{project: project, name: "active-drift-node"})
      node2 = node_fixture(%{project: project, name: "resolved-drift-node"})

      _active = drift_event_fixture(%{node: node1, project: project})
      resolved = drift_event_fixture(%{node: node2, project: project})
      ZentinelCp.Nodes.resolve_drift_event(resolved, "manual")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/drift")

      html = view |> element("form") |> render_change(%{status: "active"})
      assert html =~ "active-drift-node"
      refute html =~ "resolved-drift-node"
    end

    test "filters by resolved status", %{conn: conn, project: project} do
      node1 = node_fixture(%{project: project, name: "active-drift-node"})
      node2 = node_fixture(%{project: project, name: "resolved-drift-node"})

      _active = drift_event_fixture(%{node: node1, project: project})
      resolved = drift_event_fixture(%{node: node2, project: project})
      ZentinelCp.Nodes.resolve_drift_event(resolved, "manual")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/drift")

      html = view |> element("form") |> render_change(%{status: "resolved"})
      assert html =~ "resolved-drift-node"
      refute html =~ "active-drift-node"
    end

    test "resolves a drift event manually", %{conn: conn, project: project} do
      node = node_fixture(%{project: project, name: "resolvable-node"})
      event = drift_event_fixture(%{node: node, project: project})

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "Active"

      view
      |> element(~s|button[phx-click=resolve][phx-value-id="#{event.id}"]|)
      |> render_click()

      html = render(view)
      # Event should now show as resolved with Manual badge
      assert html =~ "Resolved"
      assert html =~ "Manual"
      # Resolve button should no longer be present for resolved events
      refute html =~ ~s|phx-value-id="#{event.id}"|
    end

    test "displays resolution type for resolved events", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      event = drift_event_fixture(%{node: node, project: project})
      ZentinelCp.Nodes.resolve_drift_event(event, "auto_corrected")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "Auto-corrected"
    end

    test "shows bundle IDs as links", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      expected_id = Ecto.UUID.generate()
      actual_id = Ecto.UUID.generate()

      _event =
        drift_event_fixture(%{
          node: node,
          project: project,
          expected_bundle_id: expected_id,
          actual_bundle_id: actual_id
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ String.slice(expected_id, 0, 8)
      assert html =~ String.slice(actual_id, 0, 8)
    end

    test "shows 'none' when actual bundle is nil", %{conn: conn, project: project} do
      node = node_fixture(%{project: project})
      _event = drift_event_fixture(%{node: node, project: project, actual_bundle_id: nil})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "none"
    end

    test "resolve all button resolves all active events", %{conn: conn, project: project} do
      node1 = node_fixture(%{project: project, name: "node-1"})
      node2 = node_fixture(%{project: project, name: "node-2"})
      _event1 = drift_event_fixture(%{node: node1, project: project})
      _event2 = drift_event_fixture(%{node: node2, project: project})

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/drift")
      assert html =~ "Resolve All (2)"

      view
      |> element(~s|button[phx-click=resolve_all]|)
      |> render_click()

      html = render(view)
      # Both events should now be resolved
      assert html =~ "Resolved</span>"
      # Active count should be 0
      assert html =~ ">Active Drifts</div><div class=\"text-2xl font-bold \">\n        0"
      # Resolve All button should no longer be present (no active events)
      refute html =~ "Resolve All"
    end
  end
end
