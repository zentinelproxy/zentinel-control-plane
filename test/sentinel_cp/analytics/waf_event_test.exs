defmodule SentinelCp.Analytics.WafEventTest do
  use SentinelCp.DataCase

  alias SentinelCp.Analytics
  alias SentinelCp.Analytics.WafEvent

  defp create_project(_) do
    {:ok, org} = SentinelCp.Orgs.create_org(%{name: "WAF Org", slug: "waf-org"})

    {:ok, project} =
      SentinelCp.Projects.create_project(%{name: "WAF Project", slug: "waf-proj", org_id: org.id})

    %{project: project}
  end

  describe "changeset/2" do
    setup [:create_project]

    test "valid changeset", %{project: project} do
      cs =
        WafEvent.changeset(%WafEvent{}, %{
          project_id: project.id,
          timestamp: DateTime.utc_now(),
          rule_type: "sqli",
          action: "blocked"
        })

      assert cs.valid?
    end

    test "validates rule_type", %{project: project} do
      cs =
        WafEvent.changeset(%WafEvent{}, %{
          project_id: project.id,
          timestamp: DateTime.utc_now(),
          rule_type: "invalid",
          action: "blocked"
        })

      refute cs.valid?
      assert errors_on(cs)[:rule_type]
    end

    test "validates action", %{project: project} do
      cs =
        WafEvent.changeset(%WafEvent{}, %{
          project_id: project.id,
          timestamp: DateTime.utc_now(),
          rule_type: "xss",
          action: "invalid"
        })

      refute cs.valid?
      assert errors_on(cs)[:action]
    end
  end

  describe "ingest_waf_events/1" do
    setup [:create_project]

    test "bulk inserts WAF events", %{project: project} do
      events = [
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "rule_type" => "sqli",
          "action" => "blocked",
          "severity" => "high",
          "client_ip" => "1.2.3.4",
          "method" => "POST",
          "path" => "/api/login"
        },
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "rule_type" => "xss",
          "action" => "logged",
          "severity" => "medium",
          "client_ip" => "5.6.7.8",
          "method" => "GET",
          "path" => "/search"
        }
      ]

      assert {:ok, 2} = Analytics.ingest_waf_events(events)
    end
  end

  describe "queries" do
    setup [:create_project]

    setup %{project: project} do
      now = DateTime.utc_now()

      events = [
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(now),
          "rule_type" => "sqli",
          "action" => "blocked",
          "severity" => "high",
          "client_ip" => "1.2.3.4",
          "method" => "POST",
          "path" => "/api/login"
        },
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(now),
          "rule_type" => "xss",
          "action" => "blocked",
          "severity" => "medium",
          "client_ip" => "1.2.3.4",
          "method" => "GET",
          "path" => "/search"
        },
        %{
          "project_id" => project.id,
          "timestamp" => DateTime.to_iso8601(now),
          "rule_type" => "scanner",
          "action" => "logged",
          "severity" => "low",
          "client_ip" => "9.8.7.6",
          "method" => "GET",
          "path" => "/.env"
        }
      ]

      {:ok, 3} = Analytics.ingest_waf_events(events)
      :ok
    end

    test "list_waf_events/2 returns events", %{project: project} do
      events = Analytics.list_waf_events(project.id)
      assert length(events) == 3
    end

    test "list_waf_events/2 filters by rule_type", %{project: project} do
      events = Analytics.list_waf_events(project.id, rule_type: "sqli")
      assert length(events) == 1
      assert hd(events).rule_type == "sqli"
    end

    test "list_waf_events/2 filters by action", %{project: project} do
      events = Analytics.list_waf_events(project.id, action: "logged")
      assert length(events) == 1
    end

    test "get_waf_event_stats/2", %{project: project} do
      stats = Analytics.get_waf_event_stats(project.id)
      assert stats.total == 3
      assert stats.blocked == 2
      assert stats.logged == 1
    end

    test "get_top_blocked_ips/3", %{project: project} do
      ips = Analytics.get_top_blocked_ips(project.id)
      assert length(ips) == 1
      assert {"1.2.3.4", 2} = hd(ips)
    end

    test "get_top_blocked_paths/3", %{project: project} do
      paths = Analytics.get_top_blocked_paths(project.id)
      assert length(paths) == 2
    end

    test "prune_old_waf_events/1", %{project: _project} do
      # All events are recent, so none should be pruned
      assert {:ok, 0} = Analytics.prune_old_waf_events(30)
    end
  end
end
