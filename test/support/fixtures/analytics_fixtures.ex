defmodule SentinelCp.AnalyticsFixtures do
  @moduledoc """
  Test helpers for creating analytics entities.
  """

  alias SentinelCp.Repo
  alias SentinelCp.Analytics.{ServiceMetric, RequestLog}

  def metric_fixture(attrs \\ %{}) do
    project = attrs[:project] || SentinelCp.ProjectsFixtures.project_fixture()
    service = attrs[:service] || SentinelCp.ServicesFixtures.service_fixture(%{project: project})

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, metric} =
      %ServiceMetric{}
      |> ServiceMetric.changeset(%{
        service_id: service.id,
        project_id: project.id,
        period_start: attrs[:period_start] || now,
        period_seconds: attrs[:period_seconds] || 60,
        request_count: attrs[:request_count] || 100,
        error_count: attrs[:error_count] || 5,
        latency_p50_ms: attrs[:latency_p50_ms] || 25,
        latency_p95_ms: attrs[:latency_p95_ms] || 120,
        latency_p99_ms: attrs[:latency_p99_ms] || 450,
        bandwidth_in_bytes: attrs[:bandwidth_in_bytes] || 50_000,
        bandwidth_out_bytes: attrs[:bandwidth_out_bytes] || 200_000,
        status_2xx: attrs[:status_2xx] || 90,
        status_3xx: attrs[:status_3xx] || 2,
        status_4xx: attrs[:status_4xx] || 5,
        status_5xx: attrs[:status_5xx] || 3,
        top_paths: attrs[:top_paths] || %{"/api/users" => 50, "/api/health" => 30},
        top_consumers: attrs[:top_consumers] || %{"10.0.0.1" => 60, "10.0.0.2" => 40}
      })
      |> Repo.insert()

    metric
  end

  def request_log_fixture(attrs \\ %{}) do
    project = attrs[:project] || SentinelCp.ProjectsFixtures.project_fixture()
    service = attrs[:service] || SentinelCp.ServicesFixtures.service_fixture(%{project: project})

    {:ok, log} =
      %RequestLog{}
      |> RequestLog.changeset(%{
        service_id: service.id,
        project_id: project.id,
        node_id: attrs[:node_id],
        timestamp: attrs[:timestamp] || DateTime.utc_now(),
        method: attrs[:method] || "GET",
        path: attrs[:path] || "/api/users",
        status: attrs[:status] || 200,
        latency_ms: attrs[:latency_ms] || 45,
        client_ip: attrs[:client_ip] || "10.0.0.1",
        user_agent: attrs[:user_agent] || "curl/7.68.0",
        request_size: attrs[:request_size] || 256,
        response_size: attrs[:response_size] || 1024
      })
      |> Repo.insert()

    log
  end
end
