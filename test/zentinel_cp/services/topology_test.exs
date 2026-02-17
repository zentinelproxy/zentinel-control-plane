defmodule ZentinelCp.Services.TopologyTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.UpstreamGroupFixtures
  import ZentinelCp.AuthPolicyFixtures
  import ZentinelCp.CertificateFixtures

  describe "get_topology_data/1" do
    test "returns empty structure for project with no services" do
      project = project_fixture()
      data = Services.get_topology_data(project.id)

      assert data.services == []
      assert data.upstream_groups == []
      assert data.auth_policies == []
      assert data.certificates == []
      assert data.middlewares == []
      assert data.edges == []
    end

    test "returns services as topology nodes" do
      project = project_fixture()
      service = service_fixture(%{project: project})

      data = Services.get_topology_data(project.id)

      assert length(data.services) == 1
      [node] = data.services
      assert node.id == service.id
      assert node.name == service.name
      assert node.type == "service"
      assert node.status == "enabled"
      assert node.metadata.route_path == service.route_path
    end

    test "builds edges for service -> upstream group relationships" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, service} =
        Services.create_service(%{
          name: "linked-service",
          route_path: "/api/*",
          upstream_group_id: group.id,
          project_id: project.id
        })

      data = Services.get_topology_data(project.id)

      upstream_edges = Enum.filter(data.edges, &(&1.edge_type == "upstream"))
      assert length(upstream_edges) == 1
      [edge] = upstream_edges
      assert edge.source == service.id
      assert edge.target == group.id
    end

    test "builds edges for service -> auth policy relationships" do
      project = project_fixture()
      policy = auth_policy_fixture(%{project: project})

      {:ok, service} =
        Services.create_service(%{
          name: "auth-service",
          route_path: "/secure/*",
          upstream_url: "http://localhost:3000",
          auth_policy_id: policy.id,
          project_id: project.id
        })

      data = Services.get_topology_data(project.id)

      auth_edges = Enum.filter(data.edges, &(&1.edge_type == "auth"))
      assert length(auth_edges) == 1
      [edge] = auth_edges
      assert edge.source == service.id
      assert edge.target == policy.id
    end

    test "includes all entity types in topology data" do
      project = project_fixture()
      _service = service_fixture(%{project: project})
      _group = upstream_group_fixture(%{project: project})
      _policy = auth_policy_fixture(%{project: project})
      _cert = certificate_fixture(%{project: project})

      data = Services.get_topology_data(project.id)

      assert length(data.services) == 1
      assert length(data.upstream_groups) == 1
      assert length(data.auth_policies) == 1
      assert length(data.certificates) == 1
    end
  end
end
