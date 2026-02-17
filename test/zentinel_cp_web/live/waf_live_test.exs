defmodule ZentinelCpWeb.WafLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ZentinelCp.{Accounts, Analytics, Orgs, Projects}

  setup do
    {:ok, org} = Orgs.create_org(%{name: "WAF Test Org", slug: "waf-test-org"})

    {:ok, project} =
      Projects.create_project(%{name: "WAF Test", slug: "waf-test", org_id: org.id})

    {:ok, user} = Accounts.register_user(%{email: "waf@test.com", password: "password123456"})
    Orgs.add_member(org, user, "admin")

    # Insert some WAF events
    events = [
      %{
        "project_id" => project.id,
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "rule_type" => "sqli",
        "action" => "blocked",
        "severity" => "high",
        "client_ip" => "10.0.0.1",
        "method" => "POST",
        "path" => "/api/users",
        "matched_data" => "' OR 1=1",
        "user_agent" => "curl/7.68.0",
        "request_headers" => %{"content-type" => "application/json"},
        "metadata" => %{"score" => 95}
      }
    ]

    Analytics.ingest_waf_events(events)
    [event] = Analytics.list_waf_events(project.id, time_range: 1)

    %{org: org, project: project, user: user, event: event}
  end

  test "renders WAF dashboard", %{conn: conn, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.slug}/waf")

    assert html =~ "WAF Events"
    assert html =~ "Total Events"
    assert html =~ "Blocked"
  end

  test "renders org-scoped WAF dashboard", %{conn: conn, org: org, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/waf")

    assert html =~ "WAF Events"
  end

  test "renders time-series section", %{conn: conn, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.slug}/waf")

    assert html =~ "Event Timeline"
  end

  test "renders WAF event show page", %{conn: conn, project: project, user: user, event: event} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.slug}/waf/#{event.id}")

    assert html =~ "WAF Event"
    assert html =~ "sqli"
    assert html =~ "blocked"
    assert html =~ "10.0.0.1"
    assert html =~ "/api/users"
    assert html =~ "Event Info"
    assert html =~ "Request Headers"
    assert html =~ "Metadata"
  end

  test "renders org-scoped WAF event show page", %{
    conn: conn,
    org: org,
    project: project,
    user: user,
    event: event
  } do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/waf/#{event.id}")

    assert html =~ "WAF Event"
    assert html =~ "sqli"
  end

  test "redirects on non-existent WAF event", %{conn: conn, project: project, user: user} do
    conn = log_in_user(conn, user)
    fake_id = Ecto.UUID.generate()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/projects/#{project.slug}/waf/#{fake_id}")

    assert path =~ "/waf"
    assert flash["error"] =~ "not found"
  end

  test "sidebar contains WAF Events link", %{conn: conn, org: org, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/waf")

    assert html =~ "WAF Events"
    assert html =~ "hero-shield-check"
  end
end
