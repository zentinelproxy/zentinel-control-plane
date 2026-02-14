defmodule SentinelCpWeb.NotificationsLiveTest do
  use SentinelCpWeb.ConnCase

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.ProjectsFixtures
  import SentinelCp.NotificationFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "Index (Overview)" do
    test "renders stats and recent events", %{conn: conn, project: project} do
      event_fixture(%{project: project, type: "rollout.started"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications")

      assert html =~ "Notifications"
      assert html =~ "Total"
      assert html =~ "Delivered"
      assert html =~ "rollout.started"
    end

    test "shows empty state", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications")

      assert html =~ "No events emitted yet"
    end
  end

  describe "Channels" do
    test "lists channels", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Slack Alerts"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications/channels")

      assert html =~ "Notification Channels"
      assert html =~ channel.name
      assert html =~ "slack"
    end

    test "shows empty state", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications/channels")

      assert html =~ "No notification channels yet"
    end

    test "creates slack channel", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/channels/new")

      assert render(view) =~ "Create Notification Channel"

      view
      |> form("form", %{
        "name" => "My Slack Channel",
        "type" => "slack",
        "enabled" => "true",
        "webhook_url" => "https://hooks.slack.com/services/test"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/notifications/channels/"
    end

    test "creates webhook channel", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/channels/new")

      view
      |> element("select[name='type']")
      |> render_change(%{"type" => "webhook"})

      view
      |> form("form", %{
        "name" => "My Webhook",
        "type" => "webhook",
        "enabled" => "true",
        "url" => "https://example.com/webhook"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/notifications/channels/"
    end

    test "deletes channel", %{conn: conn, project: project} do
      channel_fixture(%{project: project, name: "To Delete"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/channels")

      view
      |> element("button[phx-click='delete']")
      |> render_click()

      refute render(view) =~ "To Delete"
    end
  end

  describe "Channel Show" do
    test "displays channel details", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Show Channel"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}")

      assert html =~ "Show Channel"
      assert html =~ "slack"
      assert html =~ "Signing Secret"
    end

    test "sends test notification", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Test Channel"})

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}")

      assert html =~ "No delivery attempts yet."

      html = render_click(view, "send_test", %{})

      # A new delivery attempt should appear in the recent deliveries table
      refute html =~ "No delivery attempts yet."
    end
  end

  describe "Rules" do
    test "lists rules", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      rule = rule_fixture(%{project: project, channel: channel, name: "Rollout Alerts"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications/rules")

      assert html =~ "Notification Rules"
      assert html =~ rule.name
      assert html =~ rule.event_pattern
    end

    test "creates rule", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Test Channel"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/rules/new")

      assert render(view) =~ "Create Notification Rule"

      view
      |> form("form", %{
        "name" => "New Rule",
        "event_pattern" => "rollout.*",
        "channel_id" => channel.id,
        "enabled" => "true"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/notifications/rules/"
    end

    test "deletes rule", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      rule_fixture(%{project: project, channel: channel, name: "To Delete"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/rules")

      view
      |> element("button[phx-click='delete']")
      |> render_click()

      refute render(view) =~ "To Delete"
    end
  end

  describe "Rule Show" do
    test "displays rule details", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Slack Channel"})

      rule =
        rule_fixture(%{
          project: project,
          channel: channel,
          name: "Show Rule",
          event_pattern: "drift.*"
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/rules/#{rule.id}")

      assert html =~ "Show Rule"
      assert html =~ "drift.*"
      assert html =~ "Slack Channel"
    end
  end

  describe "Delivery Show" do
    test "renders attempt details", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Detail Channel"})
      event = event_fixture(%{project: project, type: "rollout.started"})

      attempt =
        delivery_attempt_fixture(%{
          project: project,
          channel: channel,
          event: event,
          status: "delivered",
          http_status: 200,
          latency_ms: 85,
          request_body: ~s({"blocks": []}),
          response_body: ~s(ok)
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/delivery/#{attempt.id}")

      assert html =~ "Delivery Attempt"
      assert html =~ "delivered"
      assert html =~ "200"
      assert html =~ "85ms"
      assert html =~ "Detail Channel"
      assert html =~ "rollout.started"
    end

    test "shows request and response body", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      event = event_fixture(%{project: project})

      attempt =
        delivery_attempt_fixture(%{
          project: project,
          channel: channel,
          event: event,
          request_body: ~s({"test": "request"}),
          response_body: ~s({"test": "response"})
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/delivery/#{attempt.id}")

      assert html =~ "Request Body"
      assert html =~ "Response Body"
      # HTML-escaped quotes in rendered output
      assert html =~ "test"
      assert html =~ "request"
      assert html =~ "response"
      refute html =~ "Not captured"
    end

    test "shows attempt chain", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      event = event_fixture(%{project: project})

      _attempt1 =
        delivery_attempt_fixture(%{
          project: project,
          channel: channel,
          event: event,
          status: "failed",
          attempt_number: 1,
          error: "Connection refused"
        })

      attempt2 =
        delivery_attempt_fixture(%{
          project: project,
          channel: channel,
          event: event,
          status: "delivered",
          attempt_number: 2
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/notifications/delivery/#{attempt2.id}")

      assert html =~ "Attempt Chain"
      assert html =~ "Connection refused"
    end
  end

  describe "Delivery" do
    test "lists delivery attempts", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project, name: "Delivery Channel"})
      event = event_fixture(%{project: project, type: "rollout.completed"})

      delivery_attempt_fixture(%{
        project: project,
        channel: channel,
        event: event,
        status: "delivered",
        http_status: 200,
        latency_ms: 120
      })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/notifications/delivery")

      assert html =~ "Delivery Monitor"
      assert html =~ "delivered"
      assert html =~ "120ms"
    end

    test "filters by status", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      event = event_fixture(%{project: project})

      delivery_attempt_fixture(%{
        project: project,
        channel: channel,
        event: event,
        status: "failed",
        error: "Connection refused"
      })

      delivery_attempt_fixture(%{
        project: project,
        channel: channel,
        event: event,
        status: "delivered"
      })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/notifications/delivery")

      html =
        view
        |> element("form")
        |> render_change(%{"status" => "failed", "channel_id" => ""})

      assert html =~ "failed"
      assert html =~ "Connection refused"
    end

    test "retries dead-letter delivery", %{conn: conn, project: project} do
      channel = channel_fixture(%{project: project})
      event = event_fixture(%{project: project})

      attempt =
        delivery_attempt_fixture(%{
          project: project,
          channel: channel,
          event: event,
          status: "dead_letter"
        })

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/notifications/delivery")

      assert html =~ "dead_letter"

      view
      |> element("button[phx-click='retry'][phx-value-id='#{attempt.id}']")
      |> render_click()

      # After retry, a new pending attempt should be created
      assert render(view) =~ "pending"
    end
  end
end
