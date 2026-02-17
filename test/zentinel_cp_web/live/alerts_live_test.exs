defmodule ZentinelCpWeb.AlertsLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.Observability
  alias ZentinelCp.Observability.AlertState
  alias ZentinelCp.Repo

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "Active Alerts Index" do
    test "shows empty state", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/alerts")

      assert html =~ "Alerts"
      assert html =~ "No active alerts"
    end

    test "lists firing alerts", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Test Alert",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0},
          severity: "critical"
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _state} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 10.0,
          fingerprint: "test-firing"
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/alerts")

      assert html =~ "Test Alert"
      assert html =~ "critical"
      assert html =~ "firing"
    end

    test "acknowledge firing alert", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Ack Alert",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0},
          severity: "warning"
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, state} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 10.0,
          fingerprint: "test-ack"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/alerts")

      render_click(view, "acknowledge", %{"id" => state.id})

      assert render(view) =~ "Acknowledged"
    end
  end

  describe "Alert Rules" do
    test "lists rules", %{conn: conn, project: project} do
      {:ok, _rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Error Rate Rule",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0},
          severity: "warning"
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules")

      assert html =~ "Error Rate Rule"
      assert html =~ "metric"
      assert html =~ "warning"
    end

    test "deletes a rule", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "To Delete Rule",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules")

      render_click(view, "delete", %{"id" => rule.id})

      refute render(view) =~ "To Delete Rule"
    end
  end

  describe "Alert Rule New" do
    test "creates a metric rule via form", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules/new")

      assert html =~ "New Alert Rule"

      view
      |> form("form", %{
        "name" => "New Metric Rule",
        "rule_type" => "metric",
        "severity" => "critical",
        "for_seconds" => "60",
        "metric" => "error_rate",
        "operator" => ">",
        "value" => "5.0"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/alerts/rules/"
    end
  end

  describe "Alert Rule Show" do
    test "displays rule details and history", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Show Rule",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0},
          severity: "critical",
          for_seconds: 300
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules/#{rule.id}")

      assert html =~ "Show Rule"
      assert html =~ "critical"
      assert html =~ "300s"
      assert html =~ "error_rate"
    end

    test "silences and unsilences a rule", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Silence Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules/#{rule.id}")

      render_click(view, "silence", %{"hours" => "1"})

      assert render(view) =~ "silenced"

      render_click(view, "unsilence", %{})

      refute render(view) =~ "Silenced until"
    end
  end

  describe "Alert Rule Edit" do
    test "updates a rule", %{conn: conn, project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Edit Rule",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0},
          severity: "warning"
        })

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/alerts/rules/#{rule.id}/edit")

      assert html =~ "Edit Alert Rule"

      view
      |> form("form", %{
        "name" => "Updated Rule",
        "rule_type" => "metric",
        "severity" => "critical",
        "for_seconds" => "120",
        "metric" => "error_rate",
        "operator" => ">=",
        "value" => "10.0"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/alerts/rules/"

      updated = Observability.get_alert_rule!(rule.id)
      assert updated.name == "Updated Rule"
      assert updated.severity == "critical"
    end
  end
end
