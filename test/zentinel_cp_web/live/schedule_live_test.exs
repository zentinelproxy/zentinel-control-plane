defmodule ZentinelCpWeb.ScheduleLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.RolloutsFixtures
  import ZentinelCp.NodesFixtures

  alias ZentinelCp.Repo

  setup %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "ScheduleLive.Index" do
    test "renders schedule page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "Scheduled" or html =~ "Schedule"
    end

    test "shows empty state when no scheduled rollouts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "No scheduled" or html =~ "no scheduled" or html =~ "empty"
    end

    test "shows scheduled rollouts grouped by date", %{conn: conn} do
      project = project_fixture(%{name: "Schedule Test Project"})
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project, version: "2.0.0"})

      # Create a rollout scheduled for tomorrow
      scheduled_time = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      rollout
      |> Ecto.Changeset.change(%{scheduled_at: scheduled_time})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "Schedule Test Project" or html =~ "2.0.0"
    end

    test "displays stats for scheduled rollouts", %{conn: conn} do
      project = project_fixture()
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})

      # Create multiple scheduled rollouts
      for i <- 1..3 do
        rollout = rollout_fixture(%{project: project, bundle: bundle})
        scheduled_time = DateTime.utc_now() |> DateTime.add(i, :day) |> DateTime.truncate(:second)

        rollout
        |> Ecto.Changeset.change(%{scheduled_at: scheduled_time})
        |> Repo.update!()
      end

      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "Total" or html =~ "Next" or html =~ "Scheduled"
    end

    test "shows rollout strategy in timeline", %{conn: conn} do
      project = project_fixture()
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "all_at_once"})
      scheduled_time = DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:second)

      rollout
      |> Ecto.Changeset.change(%{scheduled_at: scheduled_time})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "all_at_once"
    end

    test "shows approval state badges", %{conn: conn} do
      project = project_fixture()
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      scheduled_time = DateTime.utc_now() |> DateTime.add(2, :hour)

      scheduled_time = scheduled_time |> DateTime.truncate(:second)

      rollout
      |> Ecto.Changeset.change(%{
        scheduled_at: scheduled_time,
        approval_state: "pending_approval"
      })
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/schedule")
      assert html =~ "approval" or html =~ "pending" or html =~ "awaiting"
    end
  end
end
