defmodule ZentinelCp.AnalyticsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Analytics

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.AnalyticsFixtures

  setup do
    project = project_fixture()
    service = service_fixture(%{project: project})
    %{project: project, service: service}
  end

  describe "ingest_metrics/1" do
    test "bulk inserts metric records", %{project: project, service: service} do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      metrics = [
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "period_start" => now,
          "request_count" => 100,
          "error_count" => 5,
          "latency_p50_ms" => 25,
          "status_2xx" => 90,
          "status_4xx" => 5,
          "status_5xx" => 5
        },
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "period_start" => now,
          "request_count" => 200,
          "error_count" => 10
        }
      ]

      assert {:ok, 2} = Analytics.ingest_metrics(metrics)
    end

    test "handles empty list" do
      assert {:ok, 0} = Analytics.ingest_metrics([])
    end
  end

  describe "ingest_request_logs/1" do
    test "bulk inserts request log entries", %{project: project, service: service} do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      logs = [
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "timestamp" => now,
          "method" => "GET",
          "path" => "/api/users",
          "status" => 200,
          "latency_ms" => 45,
          "client_ip" => "10.0.0.1"
        },
        %{
          "service_id" => service.id,
          "project_id" => project.id,
          "timestamp" => now,
          "method" => "POST",
          "path" => "/api/users",
          "status" => 201,
          "latency_ms" => 120
        }
      ]

      assert {:ok, 2} = Analytics.ingest_request_logs(logs)
    end
  end

  describe "get_service_metrics/3" do
    test "returns metrics within time range", %{project: project, service: service} do
      _metric = metric_fixture(%{project: project, service: service})

      metrics = Analytics.get_service_metrics(service.id, 1)
      assert length(metrics) >= 1
      assert hd(metrics).service_id == service.id
    end

    test "returns empty list when no data", %{service: service} do
      assert Analytics.get_service_metrics(service.id, 1) == []
    end
  end

  describe "get_project_metrics/2" do
    test "returns aggregated metrics for project", %{project: project, service: service} do
      _metric = metric_fixture(%{project: project, service: service, request_count: 150})

      result = Analytics.get_project_metrics(project.id, 1)
      assert result.total_requests >= 150
    end

    test "returns zeros when no data", %{project: project} do
      result = Analytics.get_project_metrics(project.id, 1)
      assert result.total_requests == 0
    end
  end

  describe "get_top_services/2" do
    test "returns services sorted by request count", %{project: project, service: service} do
      _metric = metric_fixture(%{project: project, service: service, request_count: 500})

      services = Analytics.get_top_services(project.id, 1)
      assert length(services) >= 1
      assert hd(services).service_id == service.id
      assert hd(services).total_requests >= 500
    end
  end

  describe "get_status_distribution/2" do
    test "returns status code counts", %{project: project, service: service} do
      _metric =
        metric_fixture(%{
          project: project,
          service: service,
          status_2xx: 90,
          status_3xx: 2,
          status_4xx: 5,
          status_5xx: 3
        })

      dist = Analytics.get_status_distribution(service.id, 1)
      assert dist.status_2xx >= 90
      assert dist.status_5xx >= 3
    end
  end

  describe "get_recent_logs/2" do
    test "returns recent request logs", %{project: project, service: service} do
      _log = request_log_fixture(%{project: project, service: service})

      logs = Analytics.get_recent_logs(service.id, limit: 10)
      assert length(logs) >= 1
      assert hd(logs).service_id == service.id
    end

    test "respects limit", %{project: project, service: service} do
      for _ <- 1..5 do
        request_log_fixture(%{project: project, service: service})
      end

      logs = Analytics.get_recent_logs(service.id, limit: 3)
      assert length(logs) == 3
    end
  end

  describe "get_waf_event/1" do
    test "returns event by ID", %{project: project} do
      {:ok, _} =
        Analytics.ingest_waf_events([
          %{
            "project_id" => project.id,
            "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
            "rule_type" => "sqli",
            "action" => "blocked",
            "severity" => "high",
            "client_ip" => "10.0.0.1",
            "method" => "POST",
            "path" => "/api/login"
          }
        ])

      [event] = Analytics.list_waf_events(project.id, time_range: 1)
      assert fetched = Analytics.get_waf_event(event.id)
      assert fetched.id == event.id
      assert fetched.rule_type == "sqli"
    end

    test "returns nil for non-existent ID" do
      assert is_nil(Analytics.get_waf_event(Ecto.UUID.generate()))
    end
  end

  describe "prune_old_logs/1" do
    test "deletes logs older than retention period", %{project: project, service: service} do
      old_time = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)
      _old_log = request_log_fixture(%{project: project, service: service, timestamp: old_time})
      _new_log = request_log_fixture(%{project: project, service: service})

      assert {:ok, 1} = Analytics.prune_old_logs(24)

      logs = Analytics.get_recent_logs(service.id)
      assert length(logs) == 1
    end

    test "returns zero when nothing to prune", %{project: project, service: service} do
      _new_log = request_log_fixture(%{project: project, service: service})

      assert {:ok, 0} = Analytics.prune_old_logs(24)
    end
  end
end
