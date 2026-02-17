defmodule ZentinelCp.Analytics.WafAnomalyTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Analytics
  alias ZentinelCp.Analytics.WafAnomaly

  defp create_project(_) do
    {:ok, org} = ZentinelCp.Orgs.create_org(%{name: "Anomaly Org", slug: "anomaly-org"})

    {:ok, project} =
      ZentinelCp.Projects.create_project(%{
        name: "Anomaly Project",
        slug: "anomaly-proj",
        org_id: org.id
      })

    %{project: project}
  end

  defp create_user(_) do
    {:ok, user} =
      ZentinelCp.Accounts.register_user(%{
        email: "anomaly@test.com",
        password: "password123456"
      })

    %{user: user}
  end

  describe "create_changeset/2" do
    setup [:create_project]

    test "valid changeset", %{project: project} do
      cs =
        WafAnomaly.create_changeset(%WafAnomaly{}, %{
          project_id: project.id,
          anomaly_type: "spike",
          severity: "high",
          detected_at: DateTime.utc_now() |> DateTime.truncate(:second),
          description: "Total blocks spike: 50 vs 10 expected",
          observed_value: 50.0,
          expected_mean: 10.0,
          expected_stddev: 3.0,
          deviation_sigma: 13.33
        })

      assert cs.valid?
    end

    test "validates anomaly_type", %{project: project} do
      cs =
        WafAnomaly.create_changeset(%WafAnomaly{}, %{
          project_id: project.id,
          anomaly_type: "invalid",
          detected_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      refute cs.valid?
      assert errors_on(cs)[:anomaly_type]
    end
  end

  describe "CRUD" do
    setup [:create_project, :create_user]

    test "create, list, acknowledge, resolve flow", %{project: project, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, anomaly} =
        Analytics.create_waf_anomaly(%{
          project_id: project.id,
          anomaly_type: "spike",
          severity: "high",
          detected_at: now,
          description: "Spike detected",
          observed_value: 50.0,
          expected_mean: 10.0,
          expected_stddev: 3.0,
          deviation_sigma: 13.33
        })

      assert anomaly.status == "active"

      # List
      anomalies = Analytics.list_waf_anomalies(project.id)
      assert length(anomalies) == 1

      # Stats
      stats = Analytics.get_anomaly_stats(project.id)
      assert stats.active == 1
      assert stats.acknowledged == 0

      # Acknowledge
      {:ok, acked} = Analytics.acknowledge_anomaly(anomaly.id, user.id)
      assert acked.status == "acknowledged"
      assert acked.acknowledged_by == user.id

      # Resolve
      {:ok, resolved} = Analytics.resolve_anomaly(anomaly.id)
      assert resolved.status == "resolved"
      assert resolved.resolved_at != nil
    end

    test "mark_false_positive/2", %{project: project, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, anomaly} =
        Analytics.create_waf_anomaly(%{
          project_id: project.id,
          anomaly_type: "new_vector",
          severity: "medium",
          detected_at: now,
          description: "New vector: rce"
        })

      {:ok, fp} = Analytics.mark_false_positive(anomaly.id, user.id)
      assert fp.status == "false_positive"
      assert fp.acknowledged_by == user.id
    end

    test "filter by status", %{project: project} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, a1} =
        Analytics.create_waf_anomaly(%{
          project_id: project.id,
          anomaly_type: "spike",
          severity: "high",
          detected_at: now,
          description: "Spike 1"
        })

      {:ok, _a2} =
        Analytics.create_waf_anomaly(%{
          project_id: project.id,
          anomaly_type: "ip_burst",
          severity: "medium",
          detected_at: now,
          description: "IP burst"
        })

      # Resolve a1
      Analytics.resolve_anomaly(a1.id)

      active = Analytics.list_waf_anomalies(project.id, status: "active")
      assert length(active) == 1

      resolved = Analytics.list_waf_anomalies(project.id, status: "resolved")
      assert length(resolved) == 1
    end
  end
end
