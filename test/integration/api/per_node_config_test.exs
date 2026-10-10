defmodule ZentinelCpWeb.Integration.Api.PerNodeConfigTest do
  @moduledoc """
  Integration tests proving that the control plane supports per-node
  configuration differentiation via labels, node groups, and bundle pinning.

  Nodes within the same project can receive different bundles based on:
    - Label-based rollout targeting (e.g., tier=frontend vs tier=backend)
    - Node group membership
    - Bundle pinning (locking a node to a specific version)
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Rollouts, Nodes, Bundles, Repo}
  alias ZentinelCp.Rollouts.Rollout

  import Ecto.Query, only: [from: 2]

  @moduletag :integration

  describe "per-node config differentiation" do
    setup %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn,
          scopes: [
            "nodes:read",
            "nodes:write",
            "bundles:read",
            "bundles:write",
            "rollouts:read",
            "rollouts:write"
          ]
        )

      %{api_conn: api_conn, context: context, raw_conn: conn}
    end

    test "label-based rollout targets frontend nodes with one bundle and backend with another", %{
      api_conn: api_conn,
      context: context,
      raw_conn: conn
    } do
      project = context.project

      # ── Register nodes with different labels ────────────────────────────

      frontend_nodes =
        for i <- 1..2 do
          resp =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{project.slug}/nodes/register", %{
              name: "frontend-#{i}",
              labels: %{"tier" => "frontend", "region" => "us-east"},
              version: "1.0.0"
            })
            |> json_response!(201)

          %{id: resp["node_id"], key: resp["node_key"]}
        end

      backend_nodes =
        for i <- 1..2 do
          resp =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{project.slug}/nodes/register", %{
              name: "backend-#{i}",
              labels: %{"tier" => "backend", "region" => "us-east"},
              version: "1.0.0"
            })
            |> json_response!(201)

          %{id: resp["node_id"], key: resp["node_key"]}
        end

      # ── Create two bundles with distinct configs ─────────────────────────

      frontend_bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "frontend-v1",
          config_source: """
          system { workers 2 }
          listeners { listener "http" address="0.0.0.0:8080" }
          waf { enabled true; mode "block" }
          """
        })

      backend_bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "backend-v1",
          config_source: """
          system { workers 8 }
          listeners { listener "http" address="0.0.0.0:9090" }
          rate-limit { global requests-per-second=5000 }
          """
        })

      # ── Rollout 1: Deploy frontend bundle to tier=frontend nodes ────────

      frontend_rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: frontend_bundle.id,
          target_selector: %{"type" => "labels", "labels" => %{"tier" => "frontend"}},
          strategy: "all_at_once"
        })
        |> json_response!(201)

      frontend_rollout_id = frontend_rollout_resp["id"]

      # Plan and execute
      rollout = Rollouts.get_rollout!(frontend_rollout_id)
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      # Verify only frontend nodes were targeted
      detailed = Rollouts.get_rollout_with_details(frontend_rollout_id)
      targeted_ids = detailed.steps |> Enum.flat_map(& &1.node_ids) |> MapSet.new()
      frontend_ids = MapSet.new(Enum.map(frontend_nodes, & &1.id))
      backend_ids = MapSet.new(Enum.map(backend_nodes, & &1.id))

      assert MapSet.equal?(targeted_ids, frontend_ids),
             "Expected only frontend nodes targeted"

      assert MapSet.disjoint?(targeted_ids, backend_ids),
             "Backend nodes should not be targeted"

      # Activate frontend nodes and complete rollout
      set_active_bundle(Enum.map(frontend_nodes, & &1.id), frontend_bundle.id)
      tick_until_terminal(frontend_rollout_id, max_ticks: 10)

      # ── Rollout 2: Deploy backend bundle to tier=backend nodes ──────────

      backend_rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: backend_bundle.id,
          target_selector: %{"type" => "labels", "labels" => %{"tier" => "backend"}},
          strategy: "all_at_once"
        })
        |> json_response!(201)

      backend_rollout_id = backend_rollout_resp["id"]

      rollout = Rollouts.get_rollout!(backend_rollout_id)
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      # Verify only backend nodes targeted
      detailed = Rollouts.get_rollout_with_details(backend_rollout_id)
      targeted_ids = detailed.steps |> Enum.flat_map(& &1.node_ids) |> MapSet.new()
      assert MapSet.equal?(targeted_ids, backend_ids)

      set_active_bundle(Enum.map(backend_nodes, & &1.id), backend_bundle.id)
      tick_until_terminal(backend_rollout_id, max_ticks: 10)

      # ── Verify: each tier has its own bundle ────────────────────────────

      for node <- frontend_nodes do
        db_node = Nodes.get_node!(node.id)

        assert db_node.active_bundle_id == frontend_bundle.id,
               "Frontend node #{db_node.name} should have frontend bundle"
      end

      for node <- backend_nodes do
        db_node = Nodes.get_node!(node.id)

        assert db_node.active_bundle_id == backend_bundle.id,
               "Backend node #{db_node.name} should have backend bundle"
      end

      # Verify config_source is different
      assert Bundles.get_bundle!(frontend_bundle.id).config_source =~ "waf"
      refute Bundles.get_bundle!(backend_bundle.id).config_source =~ "waf"
      assert Bundles.get_bundle!(backend_bundle.id).config_source =~ "rate-limit"
    end

    test "pinned node is excluded from rollout targeting a different bundle", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 3 nodes
      nodes =
        for i <- 1..3 do
          {node, _key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "pin-node-#{i}"
            })

          node
        end

      [node1, node2, node3] = nodes

      # Create two bundles
      bundle_a =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "pin-a-v1"
        })

      bundle_b =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "pin-b-v1"
        })

      # Pin node1 to bundle_a
      {:ok, _} = Nodes.pin_node_to_bundle(node1.id, bundle_a.id)

      # Create rollout for bundle_b targeting all nodes
      rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle_b.id,
          target_selector: %{"type" => "all"},
          strategy: "all_at_once"
        })
        |> json_response!(201)

      rollout = Rollouts.get_rollout!(rollout_resp["id"])
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      # Verify node1 was excluded (pinned to different bundle)
      detailed = Rollouts.get_rollout_with_details(rollout.id)
      targeted_ids = detailed.steps |> Enum.flat_map(& &1.node_ids)

      refute node1.id in targeted_ids,
             "Pinned node should be excluded from rollout for different bundle"

      assert node2.id in targeted_ids
      assert node3.id in targeted_ids
    end

    test "node group targeting deploys to specific group only", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 4 nodes
      nodes =
        for i <- 1..4 do
          {node, _key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "group-node-#{i}"
            })

          node
        end

      [n1, n2, n3, n4] = nodes

      # Create a node group and add n1, n2 to it
      {:ok, group} =
        Nodes.create_node_group(%{
          name: "canary-group",
          project_id: project.id
        })

      {:ok, _} = Nodes.add_node_to_group(n1.id, group.id)
      {:ok, _} = Nodes.add_node_to_group(n2.id, group.id)

      # Create bundle and rollout targeting the group
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "group-v1"
        })

      rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle.id,
          target_selector: %{"type" => "groups", "group_ids" => [group.id]},
          strategy: "all_at_once"
        })
        |> json_response!(201)

      rollout = Rollouts.get_rollout!(rollout_resp["id"])
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      # Verify only group members are targeted
      detailed = Rollouts.get_rollout_with_details(rollout.id)
      targeted_ids = detailed.steps |> Enum.flat_map(& &1.node_ids) |> MapSet.new()

      assert n1.id in targeted_ids
      assert n2.id in targeted_ids
      refute n3.id in targeted_ids
      refute n4.id in targeted_ids
    end

    test "direct bundle assignment to specific nodes bypasses rollout", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 3 nodes
      nodes =
        for i <- 1..3 do
          {node, _key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "assign-node-#{i}"
            })

          node
        end

      [n1, n2, n3] = nodes

      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "direct-v1"
        })

      # Assign to only n1 and n2 via API
      assign_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/bundles/#{bundle.id}/assign", %{
          node_ids: [n1.id, n2.id]
        })
        |> json_response!(200)

      assert assign_resp["assigned"] == 2

      # Verify n1, n2 have staged_bundle_id set, n3 does not
      assert Nodes.get_node!(n1.id).staged_bundle_id == bundle.id
      assert Nodes.get_node!(n2.id).staged_bundle_id == bundle.id
      refute Nodes.get_node!(n3.id).staged_bundle_id == bundle.id
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp set_active_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [active_bundle_id: bundle_id])
  end

  defp tick_until_terminal(rollout_id, opts) do
    max_ticks = Keyword.get(opts, :max_ticks, 20)

    Enum.reduce_while(1..max_ticks, nil, fn _i, _acc ->
      rollout = Rollouts.get_rollout!(rollout_id)

      if rollout.state in ~w(completed cancelled failed) do
        {:halt, rollout}
      else
        Rollouts.tick_rollout(rollout)
        {:cont, rollout}
      end
    end)
    |> case do
      %Rollout{} = r -> r
      _ -> Rollouts.get_rollout!(rollout_id)
    end
  end
end
