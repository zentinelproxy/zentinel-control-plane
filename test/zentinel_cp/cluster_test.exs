defmodule ZentinelCp.ClusterTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Cluster.{LeaderElection, Health, Backup}

  import ZentinelCp.ProjectsFixtures

  # ─── 19.1 Leader Election ───────────────────────────────────────

  describe "leader election" do
    test "leader? returns true in single-instance mode" do
      # In test (SQLite), always returns true
      assert LeaderElection.leader?() == true
    end

    test "node_name returns the current node" do
      assert LeaderElection.node_name() == node()
    end
  end

  # ─── 19.1 Health Checks ─────────────────────────────────────────

  describe "health checks" do
    test "alive? returns true" do
      assert Health.alive?() == true
    end

    test "ready? checks database connectivity" do
      assert Health.ready?() == true
    end

    test "check returns comprehensive health status" do
      {status, details} = Health.check()
      assert status == :ok
      assert details.database.status == :ok
      assert details.memory.status == :ok
      assert details.cluster.status == :ok
    end

    test "cluster_info returns node information" do
      info = Health.cluster_info()
      assert info.node == node()
      assert info.cluster_size >= 1
      assert info.uptime_seconds >= 0
      assert is_list(info.connected_nodes)
    end
  end

  # ─── 19.3 Backup & Recovery ─────────────────────────────────────

  describe "backup and recovery" do
    test "system_inventory returns resource counts" do
      project_fixture()

      inventory = Backup.system_inventory()
      assert inventory.projects >= 1
      assert inventory.generated_at != nil
      assert inventory.cluster_info.node == node()
    end

    test "export_all_projects returns project configs" do
      project = project_fixture()

      exports = Backup.export_all_projects()
      assert length(exports) >= 1

      {slug, config} = Enum.find(exports, fn {s, _} -> s == project.slug end)
      assert slug == project.slug
      assert config["version"] == "1.0"
    end

    test "generate_runbook returns markdown document" do
      project_fixture()

      runbook = Backup.generate_runbook()
      assert is_binary(runbook)
      assert runbook =~ "Disaster Recovery Runbook"
      assert runbook =~ "Database Recovery"
      assert runbook =~ "Bundle Storage Recovery"
      assert runbook =~ "RTO/RPO Targets"
    end

    test "system_inventory includes all resource types" do
      inventory = Backup.system_inventory()

      expected_keys = [
        :projects,
        :services,
        :nodes,
        :bundles,
        :active_rollouts,
        :environments,
        :upstream_groups,
        :policies,
        :slos,
        :alert_rules,
        :federation_peers,
        :cluster_info,
        :generated_at
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(inventory, key), "Missing key: #{key}"
      end)
    end
  end
end
