defmodule ZentinelCp.Services.CircuitBreakerStatusTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services
  alias ZentinelCp.Services.CircuitBreakerStatus

  defp create_project_node_and_group(_) do
    {:ok, org} = ZentinelCp.Orgs.create_org(%{name: "CB Org", slug: "cb-org"})

    {:ok, project} =
      ZentinelCp.Projects.create_project(%{name: "CB Project", slug: "cb-proj", org_id: org.id})

    {:ok, node} =
      ZentinelCp.Nodes.register_node(%{
        name: "cb-node-1",
        project_id: project.id,
        hostname: "cb-node-1.local"
      })

    {:ok, group} =
      Services.create_upstream_group(%{
        name: "api-backend",
        slug: "api-backend",
        project_id: project.id
      })

    %{project: project, node: node, group: group}
  end

  describe "changeset/2" do
    setup [:create_project_node_and_group]

    test "valid changeset", %{node: node, group: group} do
      cs =
        CircuitBreakerStatus.changeset(%CircuitBreakerStatus{}, %{
          upstream_group_id: group.id,
          node_id: node.id,
          state: "closed"
        })

      assert cs.valid?
    end

    test "validates state inclusion", %{node: node, group: group} do
      cs =
        CircuitBreakerStatus.changeset(%CircuitBreakerStatus{}, %{
          upstream_group_id: group.id,
          node_id: node.id,
          state: "invalid"
        })

      refute cs.valid?
      assert errors_on(cs)[:state]
    end

    test "requires upstream_group_id and node_id" do
      cs = CircuitBreakerStatus.changeset(%CircuitBreakerStatus{}, %{state: "closed"})

      refute cs.valid?
      assert errors_on(cs)[:upstream_group_id]
      assert errors_on(cs)[:node_id]
    end
  end

  describe "upsert" do
    setup [:create_project_node_and_group]

    test "upserts circuit breaker status", %{node: node, group: group} do
      attrs = %{
        upstream_group_id: group.id,
        node_id: node.id,
        state: "closed",
        failure_count: 0,
        success_count: 10
      }

      {:ok, status} = Services.upsert_circuit_breaker_status(attrs)
      assert status.state == "closed"
      assert status.success_count == 10

      # Upsert with new state
      updated_attrs = Map.merge(attrs, %{state: "open", failure_count: 5})
      {:ok, updated} = Services.upsert_circuit_breaker_status(updated_attrs)
      assert updated.id == status.id
      assert updated.state == "open"
      assert updated.failure_count == 5
    end
  end

  describe "queries" do
    setup [:create_project_node_and_group]

    test "list_circuit_breaker_statuses/1", %{node: node, group: group} do
      {:ok, _} =
        Services.upsert_circuit_breaker_status(%{
          upstream_group_id: group.id,
          node_id: node.id,
          state: "open",
          failure_count: 3
        })

      statuses = Services.list_circuit_breaker_statuses(group.id)
      assert length(statuses) == 1
      assert hd(statuses).state == "open"
    end

    test "get_circuit_breaker_summary/1", %{node: node, group: group} do
      {:ok, _} =
        Services.upsert_circuit_breaker_status(%{
          upstream_group_id: group.id,
          node_id: node.id,
          state: "open",
          failure_count: 3
        })

      summary = Services.get_circuit_breaker_summary(group.id)
      assert summary.open == 1
      assert summary.closed == 0
      assert summary.half_open == 0
    end
  end
end
