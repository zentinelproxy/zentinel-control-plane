defmodule ZentinelCpWeb.Integration.Api.AgentEventPipelineTest do
  @moduledoc """
  Integration test proving the full observability pipeline:

    WAF events and metrics flow from node API → analytics storage →
    SLO computation → alert firing.
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Analytics, Nodes, Observability}
  alias ZentinelCp.Observability.AlertEvaluator

  @moduletag :integration

  describe "observability pipeline: WAF events → metrics → SLOs → alerts" do
    setup %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn,
          scopes: [
            "nodes:read",
            "nodes:write",
            "analytics:read",
            "analytics:write"
          ]
        )

      project_slug = context.project.slug

      # Register a node via API
      register_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{project_slug}/nodes/register", %{
          name: "observability-node",
          labels: %{"env" => "prod"},
          capabilities: ["proxy"],
          version: "1.0.0"
        })
        |> json_response!(201)

      node_id = register_resp["node_id"]
      node_key = register_resp["node_key"]

      # Send initial heartbeat so the node is online
      Phoenix.ConnTest.build_conn()
      |> authenticate_as_node(node_key)
      |> post("/api/v1/nodes/#{node_id}/heartbeat", %{
        health: %{"status" => "healthy"},
        metrics: %{"cpu_percent" => 20, "memory_percent" => 35},
        version: "1.0.0"
      })
      |> json_response!(200)

      # Create a service for metrics association
      service = ZentinelCp.ServicesFixtures.service_fixture(%{project: context.project})

      %{
        api_conn: api_conn,
        context: context,
        node_id: node_id,
        node_key: node_key,
        service: service,
        raw_conn: conn
      }
    end

    test "WAF events flow from node to analytics", %{
      context: context,
      node_id: node_id,
      node_key: node_key,
      raw_conn: conn
    } do
      project = context.project

      # Send WAF events via the node-authenticated endpoint
      waf_resp =
        Phoenix.ConnTest.build_conn()
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node_id}/waf-events", %{
          events: [
            %{
              rule_type: "sqli",
              rule_id: "CRS-942100",
              action: "blocked",
              severity: "high",
              client_ip: "10.0.0.99",
              method: "POST",
              path: "/api/login",
              matched_data: "' OR 1=1 --",
              timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
            },
            %{
              rule_type: "xss",
              rule_id: "CRS-941100",
              action: "logged",
              severity: "medium",
              client_ip: "10.0.0.50",
              method: "GET",
              path: "/search",
              timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })
        |> json_response!(200)

      assert waf_resp["events_ingested"] == 2

      # Verify events are stored in analytics
      events = Analytics.list_waf_events(project.id, time_range: 1)
      assert length(events) == 2

      rule_types = Enum.map(events, & &1.rule_type)
      assert "sqli" in rule_types
      assert "xss" in rule_types

      actions = Enum.map(events, & &1.action)
      assert "blocked" in actions
      assert "logged" in actions

      # Verify aggregated stats
      stats = Analytics.get_waf_event_stats(project.id, 1)
      assert stats.total >= 2
      assert stats.blocked >= 1
      assert stats.unique_ips >= 1

      # Verify top blocked IPs
      top_ips = Analytics.get_top_blocked_ips(project.id, 1)
      blocked_ips = Enum.map(top_ips, fn {ip, _count} -> ip end)
      assert "10.0.0.99" in blocked_ips
    end

    test "metrics ingestion populates service metrics", %{
      context: context,
      node_id: node_id,
      node_key: node_key,
      service: service
    } do
      project = context.project

      # Send metrics via the node-authenticated endpoint
      metrics_resp =
        Phoenix.ConnTest.build_conn()
        |> authenticate_as_node(node_key)
        |> post("/api/v1/nodes/#{node_id}/metrics", %{
          metrics: [
            %{
              service_id: service.id,
              project_id: project.id,
              period_start: DateTime.utc_now() |> DateTime.to_iso8601(),
              period_seconds: 60,
              request_count: 1000,
              error_count: 10,
              latency_p50_ms: 25,
              latency_p95_ms: 100,
              latency_p99_ms: 200,
              status_2xx: 950,
              status_3xx: 20,
              status_4xx: 20,
              status_5xx: 10
            }
          ]
        })
        |> json_response!(200)

      assert metrics_resp["metrics_ingested"] == 1

      # Verify metrics are queryable
      project_metrics = Analytics.get_project_metrics(project.id, 1)
      assert project_metrics.total_requests >= 1000
      assert project_metrics.total_5xx >= 10
    end

    test "SLO computation reflects ingested metrics", %{
      context: context,
      service: service
    } do
      project = context.project

      # Ingest metrics directly for simplicity
      Analytics.ingest_metrics([
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "period_start" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "period_seconds" => 60,
          "request_count" => 1000,
          "error_count" => 10,
          "status_2xx" => 950,
          "status_3xx" => 20,
          "status_4xx" => 20,
          "status_5xx" => 10
        }
      ])

      # Create an SLO targeting availability
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          service_id: service.id,
          name: "API Availability",
          sli_type: "availability",
          target: 99.0,
          window_days: 1
        })

      # Compute the SLI from ingested metrics
      {:ok, computed} = Observability.compute_sli(slo)

      assert computed.error_budget_remaining != nil
      assert computed.burn_rate != nil
      assert computed.last_computed_at != nil
    end

    test "alert rule fires on high error rate from ingested metrics", %{
      context: context,
      service: service
    } do
      project = context.project

      # Ingest metrics with a high error rate (20%)
      Analytics.ingest_metrics([
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "period_start" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "period_seconds" => 60,
          "request_count" => 100,
          "error_count" => 20,
          "status_2xx" => 80,
          "status_5xx" => 20
        }
      ])

      # Create an alert rule that fires when error_rate > 10%
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "High Error Rate",
          rule_type: "metric",
          severity: "critical",
          for_seconds: 0,
          condition: %{
            "metric" => "error_rate",
            "operator" => ">",
            "value" => 10.0,
            "window_minutes" => 5
          }
        })

      # Evaluate the rule against the ingested data
      {:ok, _} = AlertEvaluator.evaluate_rule(rule)

      # Verify that the alert is firing
      alert_states = Observability.active_alert_states(rule.id)
      assert alert_states != []

      firing = hd(alert_states)
      assert firing.value > 10.0
    end
  end
end
