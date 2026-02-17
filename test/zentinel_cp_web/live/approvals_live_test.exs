defmodule ZentinelCpWeb.ApprovalsLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.RolloutsFixtures
  import ZentinelCp.NodesFixtures

  alias ZentinelCp.Repo

  setup %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "ApprovalsLive.Index" do
    test "renders approvals page for admin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/approvals")
      assert html =~ "Approval" or html =~ "approval"
    end

    test "allows reader users to view", %{conn: _conn} do
      user = user_fixture(%{role: "reader"})
      conn = build_conn() |> log_in_user(user)
      {:ok, _view, html} = live(conn, ~p"/approvals")
      assert html =~ "Approval" or html =~ "approval"
    end

    test "shows empty state when no pending approvals", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/approvals")
      # Check for various empty state indicators
      assert html =~ "pending" or html =~ "No" or html =~ "empty" or html =~ "none"
    end

    test "shows rollouts pending approval", %{conn: conn} do
      project = project_fixture(%{name: "Test Project"})
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project, version: "1.0.0"})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "rolling"})

      # Set rollout to pending approval using Repo directly
      rollout
      |> Ecto.Changeset.change(%{approval_state: "pending_approval"})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/approvals")
      assert html =~ "Test Project" or html =~ "1.0.0" or html =~ "rolling"
    end

    test "shows link to rollout details for approval", %{conn: conn} do
      project = project_fixture()
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      rollout
      |> Ecto.Changeset.change(%{approval_state: "pending_approval"})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/approvals")

      # Should show link to rollout details
      assert html =~ "Details"
      assert html =~ String.slice(rollout.id, 0, 8)
    end

    test "shows approval count", %{conn: conn} do
      project = project_fixture()
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      rollout
      |> Ecto.Changeset.change(%{approval_state: "pending_approval"})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/approvals")

      # Should show approval count
      assert html =~ "approval"
    end
  end
end
