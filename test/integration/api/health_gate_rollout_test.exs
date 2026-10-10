defmodule ZentinelCpWeb.Integration.Api.HealthGateRolloutTest do
  @moduledoc """
  Integration tests proving that rollout health gates block progression
  when nodes report unhealthy metrics, and that fixing the node allows
  the rollout to complete.

  Health gates read from `NodeHeartbeat` records:
    - error_rate gate:  latest_heartbeat.metrics["error_rate"]
    - latency gate:     latest_heartbeat.metrics["latency_p99_ms"]
    - heartbeat gate:   latest_heartbeat.health["status"] == "healthy"
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Rollouts, Nodes, Repo}
  alias ZentinelCp.Rollouts.Rollout

  import Ecto.Query, only: [from: 2]

  @moduletag :integration

  describe "health gate enforcement during rollouts" do
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

      %{api_conn: api_conn, context: context}
    end

    test "error rate health gate blocks step verification until node recovers", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 4 nodes using fixtures (no heartbeat records yet)
      nodes =
        for i <- 1..4 do
          {node, key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "hg-err-node-#{i}"
            })

          %{id: node.id, key: key}
        end

      # Create bundle and rollout with error rate gate
      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "hg-err-v1"
        })

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 2,
          progress_deadline_seconds: 600,
          health_gates: %{"max_error_rate" => 5.0}
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      # Plan rollout
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      [step1, step2] = detailed.steps

      # Tick 1: start step (pending→running)
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Activate step1 nodes
      set_active_bundle(step1.node_ids, bundle.id)

      # Send UNHEALTHY heartbeat from one node (error_rate=15 > threshold=5)
      # This is the FIRST heartbeat for these nodes — no timestamp collision
      bad_node = Enum.find(nodes, &(&1.id == hd(step1.node_ids)))
      good_node = Enum.find(nodes, &(&1.id == List.last(step1.node_ids)))

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"error_rate" => 15.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      send_heartbeat(good_node.key, good_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"error_rate" => 1.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      # Tick 2: running→verifying (nodes activated)
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Tick 3: check_step_verifying — health gate should FAIL
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1_updated = hd(detailed.steps)

      assert step1_updated.state == "verifying",
             "Step should remain verifying due to failed health gate, got: #{step1_updated.state}"

      assert step1_updated.health_gate_failure_since != nil

      # Fix the bad node: send healthy heartbeat
      # Sleep 1s to ensure unique inserted_at (SQLite second-precision timestamps)
      Process.sleep(1_000)

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"error_rate" => 1.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      # Tick — step should now complete
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1_final = hd(detailed.steps)
      assert step1_final.state == "completed"

      # Complete batch 2
      set_active_bundle(step2.node_ids, bundle.id)

      for node_id <- step2.node_ids do
        node_info = Enum.find(nodes, &(&1.id == node_id))

        send_heartbeat(node_info.key, node_id, %{
          health: %{"status" => "healthy"},
          metrics: %{"error_rate" => 0.5},
          active_bundle_id: bundle.id,
          version: "1.0.0"
        })
      end

      final_rollout = tick_until_terminal(rollout_id, max_ticks: 15)
      assert final_rollout.state == "completed"
    end

    test "latency health gate blocks rollout progression", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 2 nodes (no heartbeat records)
      nodes =
        for i <- 1..2 do
          {node, key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "hg-lat-node-#{i}"
            })

          %{id: node.id, key: key}
        end

      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "hg-lat-v1"
        })

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 2,
          health_gates: %{"max_latency_ms" => 500}
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      [step1] = detailed.steps

      # Tick to start step
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Activate + send heartbeats with HIGH latency
      set_active_bundle(step1.node_ids, bundle.id)

      bad_node = Enum.find(nodes, &(&1.id == hd(step1.node_ids)))
      good_node = Enum.find(nodes, &(&1.id == List.last(step1.node_ids)))

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"latency_p99_ms" => 800.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      send_heartbeat(good_node.key, good_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"latency_p99_ms" => 100.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      # Tick: running→verifying
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Tick: check verifying — latency gate should FAIL
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1_updated = hd(detailed.steps)
      assert step1_updated.state == "verifying"

      # Fix: send heartbeat with low latency
      Process.sleep(1_000)

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "healthy"},
        metrics: %{"latency_p99_ms" => 100.0},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      final_rollout = tick_until_terminal(rollout_id, max_ticks: 15)
      assert final_rollout.state == "completed"
    end

    test "unhealthy heartbeat status blocks rollout", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # Create 2 nodes (no heartbeat records)
      nodes =
        for i <- 1..2 do
          {node, key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "hg-hb-node-#{i}"
            })

          %{id: node.id, key: key}
        end

      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project,
          version: "hg-hb-v1"
        })

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 2,
          health_gates: %{"heartbeat_healthy" => true}
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, {_planned, _steps}} = Rollouts.plan_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      [step1] = detailed.steps

      # Tick to start
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Activate + send UNHEALTHY heartbeat (degraded status)
      set_active_bundle(step1.node_ids, bundle.id)

      bad_node = Enum.find(nodes, &(&1.id == hd(step1.node_ids)))
      good_node = Enum.find(nodes, &(&1.id == List.last(step1.node_ids)))

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "degraded"},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      send_heartbeat(good_node.key, good_node.id, %{
        health: %{"status" => "healthy"},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      # Tick: running→verifying
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      # Tick: check verifying — heartbeat gate should FAIL
      rollout = Rollouts.get_rollout!(rollout_id)
      {:ok, _} = Rollouts.tick_rollout(rollout)

      detailed = Rollouts.get_rollout_with_details(rollout_id)
      step1_updated = hd(detailed.steps)
      assert step1_updated.state == "verifying"

      # Fix: send healthy heartbeat
      Process.sleep(1_000)

      send_heartbeat(bad_node.key, bad_node.id, %{
        health: %{"status" => "healthy"},
        active_bundle_id: bundle.id,
        version: "1.0.0"
      })

      final_rollout = tick_until_terminal(rollout_id, max_ticks: 15)
      assert final_rollout.state == "completed"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp set_active_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [active_bundle_id: bundle_id])
  end

  defp send_heartbeat(node_key, node_id, params) do
    Phoenix.ConnTest.build_conn()
    |> authenticate_as_node(node_key)
    |> post("/api/v1/nodes/#{node_id}/heartbeat", params)
    |> json_response!(200)
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
