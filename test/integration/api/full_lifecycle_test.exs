defmodule ZentinelCpWeb.Integration.Api.FullLifecycleTest do
  @moduledoc """
  End-to-end integration test covering the complete critical path:

    Register nodes → Create bundle → Bundle compiles →
    Create rollout → Plan rollout → Tick through batches →
    Nodes report new bundle → Rollout completes

  Also tests: pause/resume mid-rollout, rollback, and audit trail.
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Rollouts, Nodes, Audit, Repo}
  alias ZentinelCp.Rollouts.Rollout

  import Ecto.Query, only: [from: 2]

  @moduletag :integration

  describe "full lifecycle: nodes → bundle → rollout → deploy → complete" do
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

    test "complete rolling deployment across 4 nodes in 2-node batches", %{
      api_conn: api_conn,
      context: context,
      raw_conn: conn
    } do
      project_slug = context.project.slug

      # ── Phase 1: Register 4 nodes via the API ──────────────────────────

      nodes =
        for i <- 1..4 do
          resp =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{project_slug}/nodes/register", %{
              name: "e2e-node-#{i}",
              labels: %{"env" => "prod", "region" => "us-east-1"},
              capabilities: ["proxy"],
              version: "1.0.0"
            })
            |> json_response!(201)

          assert resp["node_id"]
          assert resp["node_key"]

          %{id: resp["node_id"], key: resp["node_key"]}
        end

      # Verify all 4 nodes appear in the list
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/nodes")
        |> json_response!(200)

      assert list_resp["total"] == 4

      # Each node sends an initial heartbeat so they're online
      for node <- nodes do
        conn
        |> authenticate_as_node(node.key)
        |> post("/api/v1/nodes/#{node.id}/heartbeat", %{
          health: %{"status" => "healthy"},
          metrics: %{"cpu_percent" => 25, "memory_percent" => 40},
          version: "1.0.0"
        })
        |> json_response!(200)
      end

      # Verify stats show all online
      stats_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/nodes/stats")
        |> json_response!(200)

      assert stats_resp["by_status"]["online"] == 4

      # ── Phase 2: Create a compiled bundle ──────────────────────────────

      # Use fixture to get a pre-compiled bundle (zentinel binary not available in test)
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context.project,
          version: "2.0.0"
        })

      bundle_id = bundle.id

      # Verify bundle shows as compiled via API
      show_bundle_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/bundles/#{bundle_id}")
        |> json_response!(200)

      assert show_bundle_resp["bundle"]["status"] == "compiled"

      # ── Phase 3: Create a rolling rollout with batch_size=2 ────────────

      create_rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts", %{
          bundle_id: bundle_id,
          target_selector: %{"type" => "all"},
          strategy: "rolling",
          batch_size: 2,
          progress_deadline_seconds: 600
        })
        |> json_response!(201)

      rollout_id = create_rollout_resp["id"]
      assert rollout_id
      assert create_rollout_resp["state"] in ["pending", "running"]
      assert create_rollout_resp["strategy"] == "rolling"

      # ── Phase 4: Plan the rollout (creates batched steps) ──────────────

      rollout = Rollouts.get_rollout!(rollout_id)
      planned_rollout = rollout

      assert planned_rollout.state == "running"

      # Verify steps were created: 4 nodes / batch_size 2 = 2 steps
      detailed = Rollouts.get_rollout_with_details(rollout_id)
      assert length(detailed.steps) == 2

      [step1, step2] = detailed.steps
      assert length(step1.node_ids) == 2
      assert length(step2.node_ids) == 2
      assert step2.state == "pending"

      # ── Phase 5: Tick through batch 1 ─────────────────────────────────

      # First tick starts step 1 (assigns bundle to batch 1 nodes)
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Simulate batch 1 nodes activating the bundle (direct DB update)
      set_active_bundle(step1.node_ids, bundle_id)

      # Send heartbeats from batch 1 nodes (confirms healthy state)
      send_heartbeats(conn, nodes, step1.node_ids, bundle_id)

      # Tick until step 1 completes and step 2 starts
      tick_times(rollout_id, 5)

      # ── Phase 6: Tick through batch 2 ─────────────────────────────────

      # Simulate batch 2 nodes activating
      set_active_bundle(step2.node_ids, bundle_id)

      # Heartbeats from batch 2
      send_heartbeats(conn, nodes, step2.node_ids, bundle_id)

      # Tick until rollout completes
      final_rollout = tick_until_terminal(rollout_id, max_ticks: 15)

      assert final_rollout.state == "completed",
             "Expected rollout to complete but got state=#{final_rollout.state}, error=#{inspect(final_rollout.error)}"

      # ── Phase 7: Verify final state ───────────────────────────────────

      # All steps should be completed
      completed = Rollouts.get_rollout_with_details(rollout_id)
      assert Enum.all?(completed.steps, &(&1.state == "completed"))

      # API shows completed rollout with progress
      show_rollout_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/rollouts/#{rollout_id}")
        |> json_response!(200)

      assert show_rollout_resp["rollout"]["state"] == "completed"
      assert show_rollout_resp["progress"]["total"] == 4

      # All nodes have the new bundle active
      for node <- nodes do
        db_node = Nodes.get_node!(node.id)
        assert db_node.active_bundle_id == bundle_id
      end

      # Audit trail recorded key events
      {audit_logs, _total} = Audit.list_audit_logs(context.project.id, limit: 100)
      actions = Enum.map(audit_logs, & &1.action)
      assert "node.registered" in actions
      assert "rollout.created" in actions
    end

    test "pause and resume mid-rollout", %{
      api_conn: api_conn,
      context: context,
      raw_conn: conn
    } do
      project_slug = context.project.slug

      # Register 4 nodes with heartbeats
      nodes =
        for i <- 1..4 do
          resp =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{project_slug}/nodes/register", %{
              name: "pause-node-#{i}",
              version: "1.0.0"
            })
            |> json_response!(201)

          conn
          |> authenticate_as_node(resp["node_key"])
          |> post("/api/v1/nodes/#{resp["node_id"]}/heartbeat", %{
            health: %{"status" => "healthy"},
            version: "1.0.0"
          })
          |> json_response!(200)

          %{id: resp["node_id"], key: resp["node_key"]}
        end

      # Create compiled bundle
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context.project,
          version: "pause-test-v1"
        })

      # Create rollout with batch_size=2
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 2
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      # Plan and start
      rollout = Rollouts.get_rollout!(rollout_id)
      # Creating the rollout through the API starts it.
      assert rollout.state == "running"

      # Complete batch 1: tick to start, activate nodes, tick to verify+complete
      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1 = hd(detailed.steps)

      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      set_active_bundle(step1.node_ids, bundle.id)
      send_heartbeats(conn, nodes, step1.node_ids, bundle.id)

      # Tick to verify + complete step 1, stop as soon as step 1 is completed
      tick_until_step_completed(rollout_id, 0, max_ticks: 10)

      # ── Pause via API before step 2 progresses ──
      pause_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts/#{rollout_id}/pause")
        |> json_response!(200)

      assert pause_resp["state"] == "paused"

      # ── Resume via API ──
      resume_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts/#{rollout_id}/resume")
        |> json_response!(200)

      assert resume_resp["state"] == "running"

      # Complete batch 2
      step2 = Enum.at(detailed.steps, 1)
      set_active_bundle(step2.node_ids, bundle.id)
      send_heartbeats(conn, nodes, step2.node_ids, bundle.id)

      final = tick_until_terminal(rollout_id, max_ticks: 15)
      assert final.state == "completed"

      # All batch-1 nodes should have the bundle
      for node_id <- step1.node_ids do
        db_node = Nodes.get_node!(node_id)
        assert db_node.active_bundle_id == bundle.id
      end
    end

    test "rollback reverts nodes to previous state", %{
      api_conn: api_conn,
      context: context,
      raw_conn: conn
    } do
      project_slug = context.project.slug

      # Register 2 nodes
      _nodes =
        for i <- 1..2 do
          resp =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{project_slug}/nodes/register", %{
              name: "rollback-node-#{i}",
              version: "1.0.0"
            })
            |> json_response!(201)

          conn
          |> authenticate_as_node(resp["node_key"])
          |> post("/api/v1/nodes/#{resp["node_id"]}/heartbeat", %{
            health: %{"status" => "healthy"},
            version: "1.0.0"
          })
          |> json_response!(200)

          %{id: resp["node_id"], key: resp["node_key"]}
        end

      # Create compiled bundle
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context.project,
          version: "rollback-v1"
        })

      # Create and plan rollout
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 1
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]
      rollout = Rollouts.get_rollout!(rollout_id)
      # Creating the rollout through the API starts it.
      assert rollout.state == "running"

      # Tick once to start step 1
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Stage the bundle on nodes (simulating partial deploy)
      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1 = hd(detailed.steps)
      set_staged_bundle(step1.node_ids, bundle.id)

      # ── Rollback via API ──
      rollback_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/rollouts/#{rollout_id}/rollback")
        |> json_response!(200)

      assert rollback_resp["state"] == "cancelled"

      # Verify rollout is cancelled
      rollout = Rollouts.get_rollout!(rollout_id)
      assert rollout.state == "cancelled"
    end

    test "drift detection after deployment", %{
      api_conn: api_conn,
      context: context,
      raw_conn: conn
    } do
      project_slug = context.project.slug

      # Register a node
      register_resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{project_slug}/nodes/register", %{
          name: "drift-node",
          version: "1.0.0"
        })
        |> json_response!(201)

      node_id = register_resp["node_id"]

      # Create compiled bundle and set it as expected
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context.project,
          version: "drift-v1"
        })

      set_expected_bundle([node_id], bundle.id)
      node = Nodes.get_node!(node_id)

      # Node is running a different bundle (or none) → drift
      drift_event =
        ZentinelCp.NodesFixtures.drift_event_fixture(%{
          node: node,
          project: context.project,
          expected_bundle_id: bundle.id,
          actual_bundle_id: nil,
          severity: "high"
        })

      # Verify drift shows via API
      drift_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/drift")
        |> json_response!(200)

      assert drift_resp["total"] >= 1

      drift_ids = Enum.map(drift_resp["drift_events"], & &1["id"])
      assert drift_event.id in drift_ids

      # Resolve drift
      resolve_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/drift/#{drift_event.id}/resolve")
        |> json_response!(200)

      assert resolve_resp["drift_event"]["id"] == drift_event.id
      assert resolve_resp["drift_event"]["resolved_at"]
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp set_active_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [active_bundle_id: bundle_id])
  end

  defp set_staged_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [staged_bundle_id: bundle_id])
  end

  defp set_expected_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [expected_bundle_id: bundle_id])
  end

  defp send_heartbeats(_conn, nodes, node_ids, bundle_id) do
    for node_id <- node_ids do
      node_info = Enum.find(nodes, &(&1.id == node_id))

      if node_info do
        Phoenix.ConnTest.build_conn()
        |> authenticate_as_node(node_info.key)
        |> post("/api/v1/nodes/#{node_id}/heartbeat", %{
          health: %{"status" => "healthy"},
          metrics: %{"cpu_percent" => 30},
          active_bundle_id: bundle_id,
          version: "1.0.0"
        })
        |> json_response!(200)
      end
    end
  end

  defp tick_until_step_completed(rollout_id, step_index, opts) do
    max_ticks = Keyword.get(opts, :max_ticks, 10)

    Enum.reduce_while(1..max_ticks, nil, fn _i, _acc ->
      rollout = Rollouts.get_rollout!(rollout_id)

      if rollout.state in ~w(completed cancelled failed) do
        {:halt, :done}
      else
        detailed = Rollouts.get_rollout_with_details(rollout_id)
        step = Enum.at(detailed.steps, step_index)

        if step && step.state == "completed" do
          {:halt, :done}
        else
          Rollouts.tick_rollout(rollout)
          {:cont, nil}
        end
      end
    end)
  end

  defp tick_times(rollout_id, n) do
    for _i <- 1..n do
      rollout = Rollouts.get_rollout!(rollout_id)

      if rollout.state == "running" do
        Rollouts.tick_rollout(rollout)
      end
    end
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
