defmodule ZentinelCpWeb.WebhooksLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.OrgsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    org = org_fixture()
    project = project_fixture(%{org: org, name: "Webhook Test Project"})
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, org: org, project: project}
  end

  describe "WebhooksLive.Index" do
    test "renders webhooks page", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "Webhook" or html =~ "GitHub"
    end

    test "shows webhook endpoint URL", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "Payload URL" or html =~ "/api/v1/webhooks/github"
    end

    test "shows content type", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "application/json"
    end

    test "shows events to subscribe", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "push"
    end

    test "shows current configuration", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "Configuration" or html =~ "Repository" or html =~ "Branch"
    end

    test "shows disabled status when no repo configured", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "Not configured" or html =~ "Disabled" or html =~ "disabled"
    end

    test "can toggle configuration form", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")

      # Show form
      view |> element(~s|button[phx-click="toggle_form"]|, "Configure") |> render_click()

      html = render(view)
      assert html =~ "GitHub Repository" or html =~ "github_repo"

      # Hide form using the specific toggle button
      view |> element(~s|button.btn-ghost[phx-click="toggle_form"]|) |> render_click()

      html = render(view)
      # Form should be hidden, but we still see the page
      assert html =~ "Webhook"
    end

    test "can save webhook configuration", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")

      # Show form
      view |> element(~s|button[phx-click="toggle_form"]|) |> render_click()

      # Submit configuration
      view
      |> form(~s|form[phx-submit="save"]|, %{
        "webhook" => %{
          "github_repo" => "acme/zentinel-configs",
          "github_branch" => "main",
          "config_path" => "zentinel.kdl"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "updated" or html =~ "acme/zentinel-configs"
    end

    test "shows enabled status when repo is configured", %{conn: conn, org: org, project: project} do
      # Update project with GitHub repo
      {:ok, _} =
        ZentinelCp.Projects.update_project(project, %{
          github_repo: "test/repo",
          github_branch: "main",
          config_path: "zentinel.kdl"
        })

      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "Enabled" or html =~ "test/repo"
    end

    test "shows how it works section", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/webhooks")
      assert html =~ "How It Works" or html =~ "how it works"
    end

    test "works with legacy project routes", %{conn: conn} do
      project = project_fixture(%{org: nil, name: "Legacy Project"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/webhooks")
      assert html =~ "Webhook" or html =~ "GitHub"
    end
  end
end
