defmodule ZentinelCp.DashboardTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Dashboard

  import ZentinelCp.OrgsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures
  import ZentinelCp.RolloutsFixtures

  describe "get_org_overview/1" do
    test "returns overview with zero counts for empty org" do
      org = org_fixture()
      overview = Dashboard.get_org_overview(org.id)

      assert overview.project_count == 0
      assert overview.node_stats.total == 0
      assert overview.active_rollouts == 0
      assert overview.recent_bundles == 0
    end

    test "counts projects and nodes" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      _node = node_fixture(%{project: project})

      overview = Dashboard.get_org_overview(org.id)
      assert overview.project_count == 1
      assert overview.node_stats.total == 1
      assert overview.node_stats.online == 1
    end

    test "counts active rollouts" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      _rollout = rollout_fixture(%{project: project})

      overview = Dashboard.get_org_overview(org.id)
      assert overview.active_rollouts == 1
    end
  end

  describe "get_project_overview/1" do
    test "returns node stats for a project" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      _node = node_fixture(%{project: project})

      overview = Dashboard.get_project_overview(project.id)
      assert overview.node_stats.total == 1
      assert overview.node_stats.online == 1
    end

    test "returns latest bundles" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      _bundle = compiled_bundle_fixture(%{project: project})

      overview = Dashboard.get_project_overview(project.id)
      assert length(overview.latest_bundles) == 1
    end
  end

  describe "get_fleet_node_stats/1" do
    test "returns zeroes for empty project list" do
      stats = Dashboard.get_fleet_node_stats([])
      assert stats.total == 0
      assert stats.online == 0
    end

    test "counts nodes by status" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      _n1 = node_fixture(%{project: project, name: "node-a"})
      _n2 = node_fixture(%{project: project, name: "node-b"})

      stats = Dashboard.get_fleet_node_stats([project.id])
      assert stats.total == 2
      assert stats.online == 2
    end
  end
end
