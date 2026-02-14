defmodule SentinelCpWeb.RolloutsLiveTest do
  use SentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.ProjectsFixtures
  import SentinelCp.RolloutsFixtures
  import SentinelCp.NodesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "RolloutsLive.Index" do
    test "renders rollouts list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts")
      assert html =~ "Rollouts"
    end

    test "shows existing rollouts", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      _rollout = rollout_fixture(%{project: project, bundle: bundle})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts")
      assert html =~ "pending"
    end

    test "strategy selector includes canary option", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/rollouts")

      # Toggle form visibility
      render_click(view, "toggle_form")
      html = render(view)

      assert html =~ "Canary"
      assert html =~ ~s(value="canary")
    end

    test "canary config section appears when canary strategy selected", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/rollouts")

      render_click(view, "toggle_form")

      # Select canary strategy
      render_click(view, "switch_strategy", %{"strategy" => "canary"})
      html = render(view)

      assert html =~ "Canary Analysis Configuration"
      assert html =~ "Error Rate Threshold"
      assert html =~ "Latency P99 Threshold"
      assert html =~ "Analysis Window"
      assert html =~ "5, 25, 50, 100"
    end

    test "canary config section hidden for rolling strategy", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/rollouts")

      render_click(view, "toggle_form")
      html = render(view)

      refute html =~ "Canary Analysis Configuration"
    end
  end

  describe "RolloutsLive.Show" do
    test "renders rollout detail page", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts/#{rollout.id}")
      assert html =~ "pending"
    end

    test "shows canary analysis section for canary rollouts", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "canary",
          canary_analysis_config: %{
            "steps" => [10, 50, 100],
            "error_rate_threshold" => 5.0
          }
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts/#{rollout.id}")
      assert html =~ "Canary Analysis"
      assert html =~ "Step 1"
      assert html =~ "10% traffic"
    end

    test "does not show canary section for rolling rollouts", %{conn: conn, project: project} do
      _node = node_fixture(%{project: project})
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "rolling"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/rollouts/#{rollout.id}")
      refute html =~ "Canary Analysis"
    end
  end
end
