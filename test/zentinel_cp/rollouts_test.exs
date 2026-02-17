defmodule ZentinelCp.RolloutsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Rollouts
  alias ZentinelCp.Rollouts.Rollout
  alias ZentinelCp.Orgs

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures
  import ZentinelCp.RolloutsFixtures
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OrgsFixtures

  describe "create_rollout/1" do
    test "creates a rollout with valid attributes" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      assert {:ok, %Rollout{} = rollout} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"},
                 strategy: "rolling",
                 batch_size: 2
               })

      assert rollout.state == "pending"
      assert rollout.strategy == "rolling"
      assert rollout.batch_size == 2
    end

    test "returns error for non-compiled bundle" do
      project = project_fixture()

      {:ok, bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: "system {}"
        })

      # Bundle is pending/failed, not compiled
      assert {:error, :bundle_not_compiled} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"}
               })
    end

    test "returns error for missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Rollouts.create_rollout(%{})
    end

    test "validates target_selector format" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "invalid"}
               })

      assert errors_on(changeset)[:target_selector]
    end

    test "validates strategy inclusion" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"},
                 strategy: "invalid"
               })

      assert errors_on(changeset)[:strategy]
    end

    test "rejects unknown health_gates keys" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"},
                 health_gates: %{"unknown_gate" => true}
               })

      assert errors_on(changeset)[:health_gates]
    end

    test "accepts valid health_gates keys" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      assert {:ok, %Rollout{}} =
               Rollouts.create_rollout(%{
                 project_id: project.id,
                 bundle_id: bundle.id,
                 target_selector: %{"type" => "all"},
                 health_gates: %{
                   "heartbeat_healthy" => true,
                   "max_error_rate" => 0.05,
                   "max_cpu_percent" => 80
                 }
               })
    end
  end

  describe "plan_rollout/1" do
    test "creates steps and node bundle statuses for rolling strategy" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})
      _node3 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, batch_size: 2})

      assert {:ok, {updated, steps}} = Rollouts.plan_rollout(rollout)
      assert updated.state == "running"
      assert updated.started_at != nil
      # 3 nodes, batch_size 2 = 2 steps
      assert length(steps) == 2
    end

    test "creates single step for all_at_once strategy" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "all_at_once"})

      assert {:ok, {_updated, steps}} = Rollouts.plan_rollout(rollout)
      assert length(steps) == 1
    end

    test "returns error when no target nodes match" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      # No nodes in this project

      rollout = rollout_fixture(%{project: project, bundle: bundle})

      assert {:error, :no_target_nodes} = Rollouts.plan_rollout(rollout)
    end

    test "creates NodeBundleStatus records for all target nodes" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      progress = Rollouts.get_rollout_progress(rollout.id)
      assert progress.total == 2
      assert progress.pending == 2
    end

    test "rejects plan_rollout on non-pending rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      # Fetch the now-running rollout
      running = Rollouts.get_rollout!(rollout.id)
      assert {:error, :invalid_state} = Rollouts.plan_rollout(running)
    end
  end

  describe "resolve_target_nodes/2" do
    test "resolves all nodes for a project" do
      project = project_fixture()
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      ids = Rollouts.resolve_target_nodes(project.id, %{"type" => "all"})
      assert Enum.sort(ids) == Enum.sort([node1.id, node2.id])
    end

    test "resolves nodes by labels" do
      project = project_fixture()
      _node1 = node_fixture(%{project: project, labels: %{"env" => "prod"}})
      node2 = node_fixture(%{project: project, labels: %{"env" => "staging"}})

      ids =
        Rollouts.resolve_target_nodes(project.id, %{
          "type" => "labels",
          "labels" => %{"env" => "staging"}
        })

      assert ids == [node2.id]
    end

    test "resolves specific node IDs" do
      ids =
        Rollouts.resolve_target_nodes("any", %{
          "type" => "node_ids",
          "node_ids" => ["abc", "def"]
        })

      assert ids == ["abc", "def"]
    end
  end

  describe "pause_rollout/1" do
    test "pauses a running rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, paused} = Rollouts.pause_rollout(running)
      assert paused.state == "paused"
    end

    test "returns error for non-running rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      assert {:error, :invalid_state} = Rollouts.pause_rollout(rollout)
    end
  end

  describe "resume_rollout/1" do
    test "resumes a paused rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, paused} = Rollouts.pause_rollout(running)
      assert {:ok, resumed} = Rollouts.resume_rollout(paused)
      assert resumed.state == "running"
    end

    test "returns error for non-paused rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert {:error, :invalid_state} = Rollouts.resume_rollout(running)
    end
  end

  describe "cancel_rollout/1" do
    test "cancels a running rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, cancelled} = Rollouts.cancel_rollout(running)
      assert cancelled.state == "cancelled"
      assert cancelled.completed_at != nil
    end

    test "cancels a paused rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, paused} = Rollouts.pause_rollout(running)
      assert {:ok, cancelled} = Rollouts.cancel_rollout(paused)
      assert cancelled.state == "cancelled"
    end

    test "returns error for pending rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      assert {:error, :invalid_state} = Rollouts.cancel_rollout(rollout)
    end
  end

  describe "rollback_rollout/1" do
    test "cancels and reverts staged_bundle_id on affected nodes" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, rolled_back} = Rollouts.rollback_rollout(running)
      assert rolled_back.state == "cancelled"

      # Node's staged_bundle_id should be cleared
      updated_node = ZentinelCp.Nodes.get_node!(node.id)
      assert updated_node.staged_bundle_id == nil
    end

    test "returns error for completed rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      # Force to completed state
      {:ok, completed} =
        rollout
        |> Rollout.state_changeset("completed")
        |> Repo.update()

      assert {:error, :invalid_state} = Rollouts.rollback_rollout(completed)
    end
  end

  describe "tick_rollout/1" do
    test "starts the first pending step" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Verify step is now running
      rollout_with_details = Rollouts.get_rollout_with_details(rollout.id)
      first_step = hd(rollout_with_details.steps)
      assert first_step.state == "running"

      # Verify node got staged_bundle_id
      updated_node = ZentinelCp.Nodes.get_node!(node.id)
      assert updated_node.staged_bundle_id == bundle.id
    end

    test "transitions step to verifying when all nodes activated" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Simulate node activating the bundle
      import Ecto.Query

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :step_verifying} = Rollouts.tick_rollout(running)
    end

    test "completes rollout when all steps done and health gates pass" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      # Create rollout with no health gates
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      # Override health_gates to empty (no gates)
      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Simulate node activation
      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Tick again — no health gates, so step should complete
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Tick once more — no more steps, rollout completes
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, %Rollout{state: "completed"}} = Rollouts.tick_rollout(running)
    end

    test "fails rollout when step deadline exceeded" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      # Very short deadline
      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          progress_deadline_seconds: 1
        })

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Wait for deadline to pass (> 1 second, so elapsed > deadline of 1)
      Process.sleep(2000)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :deadline_exceeded} = Rollouts.tick_rollout(running)

      # Verify rollout is failed
      failed = Rollouts.get_rollout!(rollout.id)
      assert failed.state == "failed"
      assert failed.error["reason"] == "step_deadline_exceeded"
    end

    test "returns :not_running for non-running rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      assert {:ok, :not_running} = Rollouts.tick_rollout(rollout)
    end

    test "pauses rollout when max_unavailable exceeded" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          batch_size: 2,
          max_unavailable: 1
        })

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Mark both nodes as offline (exceeds max_unavailable of 1)
      import Ecto.Query

      from(n in ZentinelCp.Nodes.Node, where: n.id in ^[node1.id, node2.id])
      |> Repo.update_all(set: [status: "offline"])

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :max_unavailable_exceeded} = Rollouts.tick_rollout(running)

      paused = Rollouts.get_rollout!(rollout.id)
      assert paused.state == "paused"
      assert paused.error["reason"] == "max_unavailable_exceeded"
    end

    test "progresses step when available nodes activate and unavailable within max_unavailable" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})
      node3 = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          batch_size: 3,
          max_unavailable: 1
        })

      # Disable health gates for simpler assertions
      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Mark node3 as offline (within max_unavailable of 1)
      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node3.id)
      |> Repo.update_all(set: [status: "offline"])

      # Only activate the 2 available nodes
      from(n in ZentinelCp.Nodes.Node, where: n.id in ^[node1.id, node2.id])
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      # Should progress to verifying (2 activated >= 3 - 1 required)
      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :step_verifying} = Rollouts.tick_rollout(running)
    end

    test "completes rollout with unavailable nodes within max_unavailable" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          batch_size: 2,
          max_unavailable: 1
        })

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Mark node2 offline, activate node1
      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node2.id)
      |> Repo.update_all(set: [status: "offline"])

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node1.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      # Progress through verifying → completed
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, %Rollout{state: "completed"}} = Rollouts.tick_rollout(running)
    end

    test "error_rate health gate blocks step completion" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{project: project, bundle: bundle})

      # Set health gates with error rate threshold
      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{"max_error_rate" => 0.05}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Simulate node activation
      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Add heartbeat with high error rate
      ZentinelCp.Nodes.record_heartbeat(node, %{
        health: %{"status" => "healthy"},
        metrics: %{"error_rate" => 0.10}
      })

      # Should not complete — error rate too high, waits at deadline check
      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :waiting} = Rollouts.tick_rollout(running)
    end

    test "latency health gate blocks step completion" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{project: project, bundle: bundle})

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{"max_latency_ms" => 100}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Add heartbeat with high latency
      ZentinelCp.Nodes.record_heartbeat(node, %{
        health: %{"status" => "healthy"},
        metrics: %{"latency_p99_ms" => 500}
      })

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :waiting} = Rollouts.tick_rollout(running)
    end

    test "cpu health gate blocks step completion" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{project: project, bundle: bundle})

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{"max_cpu_percent" => 80}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Add heartbeat with high CPU usage
      ZentinelCp.Nodes.record_heartbeat(node, %{
        health: %{"status" => "healthy"},
        metrics: %{"cpu_percent" => 95}
      })

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :waiting} = Rollouts.tick_rollout(running)
    end

    test "memory health gate blocks step completion" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{project: project, bundle: bundle})

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{"max_memory_percent" => 85}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Add heartbeat with high memory usage
      ZentinelCp.Nodes.record_heartbeat(node, %{
        health: %{"status" => "healthy"},
        metrics: %{"memory_percent" => 92}
      })

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :waiting} = Rollouts.tick_rollout(running)
    end

    test "health gates pass when metrics are within thresholds" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{project: project, bundle: bundle})

      import Ecto.Query

      # Set all health gates
      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(
        set: [
          health_gates: %{
            "heartbeat_healthy" => true,
            "max_error_rate" => 0.05,
            "max_latency_ms" => 100,
            "max_cpu_percent" => 80,
            "max_memory_percent" => 85
          }
        ]
      )

      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^node.id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Add heartbeat with all metrics within thresholds
      ZentinelCp.Nodes.record_heartbeat(node, %{
        health: %{"status" => "healthy"},
        metrics: %{
          "error_rate" => 0.01,
          "latency_p99_ms" => 50,
          "cpu_percent" => 40,
          "memory_percent" => 60
        }
      })

      running = Rollouts.get_rollout!(rollout.id)
      assert {:ok, :step_completed} = Rollouts.tick_rollout(running)
    end
  end

  describe "blue-green strategy" do
    test "plan_rollout creates deploy + traffic shift + final blue deploy steps" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})
      _node3 = node_fixture(%{project: project})
      _node4 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "blue_green"})

      assert {:ok, {updated, steps}} = Rollouts.plan_rollout(rollout)
      assert updated.state == "running"
      assert updated.deployment_slot == "blue"

      # Default traffic_steps [10, 50, 100] → deploy_green + 3 traffic shifts + deploy_blue = 5 steps
      assert length(steps) == 5

      # Step 0: deploy to green, weight 0
      assert Enum.at(steps, 0).deployment_slot == "green"
      assert Enum.at(steps, 0).traffic_weight == 0

      # Steps 1-3: traffic shift steps on green with weights [10, 50, 100]
      assert Enum.at(steps, 1).deployment_slot == "green"
      assert Enum.at(steps, 1).traffic_weight == 10
      assert Enum.at(steps, 2).deployment_slot == "green"
      assert Enum.at(steps, 2).traffic_weight == 50
      assert Enum.at(steps, 3).deployment_slot == "green"
      assert Enum.at(steps, 3).traffic_weight == 100

      # Step 4: deploy to blue (catch-up)
      assert Enum.at(steps, 4).deployment_slot == "blue"
      assert Enum.at(steps, 4).traffic_weight == 100

      # Green and blue nodes are split evenly
      assert length(Enum.at(steps, 0).node_ids) == 2
      assert length(Enum.at(steps, 4).node_ids) == 2
    end

    test "plan_rollout creates single step for single node" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "blue_green"})

      assert {:ok, {_updated, steps}} = Rollouts.plan_rollout(rollout)
      assert length(steps) == 1
      assert hd(steps).deployment_slot == "green"
      assert hd(steps).traffic_weight == 100
    end

    test "custom traffic_steps creates correct number of steps" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      config = %{"traffic_steps" => [25, 75, 100]}

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "blue_green",
          blue_green_config: config
        })

      assert {:ok, {_updated, steps}} = Rollouts.plan_rollout(rollout)
      # deploy_green + 3 traffic shifts + deploy_blue = 5 steps
      assert length(steps) == 5
      assert Enum.at(steps, 1).traffic_weight == 25
      assert Enum.at(steps, 2).traffic_weight == 75
      assert Enum.at(steps, 3).traffic_weight == 100
    end

    test "traffic shift steps skip bundle assignment" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      config = %{"traffic_steps" => [100], "auto_advance" => true, "advance_delay_seconds" => 0}

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "blue_green",
          blue_green_config: config,
          validation_period_seconds: 0
        })

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      details = Rollouts.get_rollout_with_details(rollout.id)
      green_node_id = hd(Enum.at(details.steps, 0).node_ids)

      # Tick 1: start deploy green step
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Simulate green node activation
      from(n in ZentinelCp.Nodes.Node, where: n.id == ^green_node_id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      # Tick: verifying → completed (deploy green)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Tick: start traffic shift step (should NOT re-assign bundles)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Traffic shift step should immediately move to verifying on next tick
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)

      # Then to validating
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_validating} = Rollouts.tick_rollout(running)
    end

    test "auto_advance false pauses after validation" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      config = %{
        "traffic_steps" => [100],
        "auto_advance" => false,
        "advance_delay_seconds" => 0
      }

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "blue_green",
          blue_green_config: config,
          validation_period_seconds: 0
        })

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      details = Rollouts.get_rollout_with_details(rollout.id)
      green_node_id = hd(Enum.at(details.steps, 0).node_ids)

      # Progress through deploy green step
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^green_node_id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Start traffic shift step
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      # Progress through verifying → validating
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_validating} = Rollouts.tick_rollout(running)

      # Next tick should pause (auto_advance = false)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :paused_for_validation} = Rollouts.tick_rollout(running)

      paused = Rollouts.get_rollout!(rollout.id)
      assert paused.state == "paused"
    end

    test "auto_advance true proceeds automatically" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      config = %{
        "traffic_steps" => [100],
        "auto_advance" => true,
        "advance_delay_seconds" => 0
      }

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "blue_green",
          blue_green_config: config,
          validation_period_seconds: 0
        })

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      details = Rollouts.get_rollout_with_details(rollout.id)
      green_node_id = hd(Enum.at(details.steps, 0).node_ids)

      # Deploy green step
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^green_node_id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Traffic shift step
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_validating} = Rollouts.tick_rollout(running)

      # Should auto-complete (auto_advance = true, validation_period = 0)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Verify the rollout is still running (blue step pending)
      updated = Rollouts.get_rollout!(rollout.id)
      assert updated.state == "running"
    end

    test "full end-to-end blue-green tick progression" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      config = %{
        "traffic_steps" => [100],
        "auto_advance" => true,
        "advance_delay_seconds" => 0
      }

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "blue_green",
          blue_green_config: config,
          validation_period_seconds: 0
        })

      import Ecto.Query

      from(r in Rollout, where: r.id == ^rollout.id)
      |> Repo.update_all(set: [health_gates: %{}])

      {:ok, _} = Rollouts.plan_rollout(rollout)

      details = Rollouts.get_rollout_with_details(rollout.id)
      green_node_id = hd(Enum.at(details.steps, 0).node_ids)
      blue_step = Enum.find(details.steps, &(&1.deployment_slot == "blue"))
      blue_node_id = hd(blue_step.node_ids)

      # Deploy green step: start → activate → verify → complete
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^green_node_id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Traffic shift step (100%): start → verify → validate → complete
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_validating} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Verify deployment_slot updated to green after 100% traffic step
      updated = Rollouts.get_rollout!(rollout.id)
      assert updated.deployment_slot == "green"

      # Blue deploy step: start → activate → verify → complete
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      from(n in ZentinelCp.Nodes.Node, where: n.id == ^blue_node_id)
      |> Repo.update_all(set: [active_bundle_id: bundle.id])

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_verifying} = Rollouts.tick_rollout(running)
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, :step_completed} = Rollouts.tick_rollout(running)

      # Rollout completed
      running = Rollouts.get_rollout!(rollout.id)
      {:ok, %Rollout{state: "completed"}} = Rollouts.tick_rollout(running)
    end

    test "advance_blue_green_traffic resumes paused rollout" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "blue_green"})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, paused} = Rollouts.pause_rollout(running)
      assert paused.state == "paused"

      {:ok, advanced} = Rollouts.advance_blue_green_traffic(paused)
      assert advanced.state == "running"
    end

    test "advance on non-blue-green returns error" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "rolling"})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, paused} = Rollouts.pause_rollout(running)

      assert {:error, :not_blue_green} = Rollouts.advance_blue_green_traffic(paused)
    end

    test "swap_blue_green_slot reverts traffic weight and swaps slot" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "blue_green"})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      assert running.deployment_slot == "blue"

      {:ok, swapped} = Rollouts.swap_blue_green_slot(running)
      assert swapped.state == "paused"
      assert swapped.deployment_slot == "green"
    end

    test "instant_rollback_blue_green cancels and clears staged bundles" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      node = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle, strategy: "blue_green"})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      # Start first step so bundle gets assigned
      {:ok, :step_started} = Rollouts.tick_rollout(running)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, cancelled} = Rollouts.instant_rollback_blue_green(running)
      assert cancelled.state == "cancelled"

      # Staged bundle should be cleared
      updated_node = ZentinelCp.Nodes.get_node!(node.id)
      assert updated_node.staged_bundle_id == nil
    end
  end

  describe "get_rollout_progress/1" do
    test "returns correct progress counts" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node1 = node_fixture(%{project: project})
      _node2 = node_fixture(%{project: project})

      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      progress = Rollouts.get_rollout_progress(rollout.id)
      assert progress.total == 2
      assert progress.pending == 2
      assert progress.active == 0
      assert progress.failed == 0
    end
  end

  describe "list_rollouts/2" do
    test "returns rollouts for a project" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _r1 = rollout_fixture(%{project: project, bundle: bundle})
      _r2 = rollout_fixture(%{project: project, bundle: bundle})

      rollouts = Rollouts.list_rollouts(project.id)
      assert length(rollouts) == 2
    end

    test "filters by state" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _rollout = rollout_fixture(%{project: project, bundle: bundle})

      assert length(Rollouts.list_rollouts(project.id, state: "pending")) == 1
      assert Rollouts.list_rollouts(project.id, state: "running") == []
    end
  end

  describe "approval workflow" do
    setup do
      # Create org with owner (admin)
      {org, admin} = org_with_owner_fixture()
      # Create another operator user and add to org
      operator = user_fixture()
      {:ok, _membership} = Orgs.add_member(org, operator, "operator")
      # Create a third operator
      operator2 = user_fixture()
      {:ok, _membership} = Orgs.add_member(org, operator2, "operator")
      # Create project in this org with approval required
      project =
        project_fixture(%{
          org: org,
          settings: %{"approval_required" => true, "approvals_needed" => 2}
        })

      bundle = compiled_bundle_fixture(%{project: project})

      %{
        org: org,
        admin: admin,
        operator: operator,
        operator2: operator2,
        project: project,
        bundle: bundle
      }
    end

    test "submit_for_approval transitions to pending_approval when required", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      assert rollout.approval_state == "not_required"

      {:ok, updated} = Rollouts.submit_for_approval(rollout)
      assert updated.approval_state == "pending_approval"
    end

    test "submit_for_approval transitions to approved when not required" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      {:ok, updated} = Rollouts.submit_for_approval(rollout)
      assert updated.approval_state == "approved"
    end

    test "approve_rollout adds approval and transitions when threshold met", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      assert rollout.approval_state == "pending_approval"

      # First approval - should stay pending_approval (need 2)
      {:ok, rollout} = Rollouts.approve_rollout(rollout, ctx.operator)
      assert rollout.approval_state == "pending_approval"
      assert Rollouts.count_approvals(rollout.id) == 1

      # Second approval - should transition to approved
      {:ok, rollout} = Rollouts.approve_rollout(rollout, ctx.operator2)
      assert rollout.approval_state == "approved"
      assert Rollouts.count_approvals(rollout.id) == 2
    end

    test "approve_rollout blocks self-approval", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)

      assert {:error, :self_approval} = Rollouts.approve_rollout(rollout, ctx.admin)
    end

    test "approve_rollout blocks duplicate approval", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      {:ok, rollout} = Rollouts.approve_rollout(rollout, ctx.operator)

      assert {:error, :already_approved} = Rollouts.approve_rollout(rollout, ctx.operator)
    end

    test "approve_rollout blocks non-operator users", ctx do
      reader = user_fixture()
      {:ok, _membership} = Orgs.add_member(ctx.org, reader, "reader")

      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)

      assert {:error, :not_authorized} = Rollouts.approve_rollout(rollout, reader)
    end

    test "reject_rollout transitions to rejected with comment", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)

      {:ok, rejected} =
        Rollouts.reject_rollout(rollout, ctx.operator, "Config has security issues")

      assert rejected.approval_state == "rejected"
      assert rejected.rejection_comment == "Config has security issues"
      assert rejected.rejected_by_id == ctx.operator.id
      assert rejected.rejected_at != nil
    end

    test "reject_rollout requires comment", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)

      assert {:error, :comment_required} = Rollouts.reject_rollout(rollout, ctx.operator, "")
      assert {:error, :comment_required} = Rollouts.reject_rollout(rollout, ctx.operator, nil)
    end

    test "plan_rollout blocks pending_approval rollouts", ctx do
      _node = node_fixture(%{project: ctx.project})

      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      assert rollout.approval_state == "pending_approval"

      assert {:error, :approval_required} = Rollouts.plan_rollout(rollout)
    end

    test "plan_rollout works after approval", ctx do
      _node = node_fixture(%{project: ctx.project})

      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      {:ok, rollout} = Rollouts.approve_rollout(rollout, ctx.operator)
      {:ok, rollout} = Rollouts.approve_rollout(rollout, ctx.operator2)

      assert rollout.approval_state == "approved"
      assert {:ok, _} = Rollouts.plan_rollout(rollout)
    end

    test "cancel_rollout works on rejected rollouts", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      {:ok, rollout} = Rollouts.reject_rollout(rollout, ctx.operator, "Not ready")

      assert rollout.state == "pending"
      assert rollout.approval_state == "rejected"

      {:ok, cancelled} = Rollouts.cancel_rollout(rollout)
      assert cancelled.state == "cancelled"
    end

    test "list_approvals returns approvals with users", ctx do
      rollout =
        rollout_fixture(%{
          project: ctx.project,
          bundle: ctx.bundle,
          created_by_id: ctx.admin.id
        })

      {:ok, rollout} = Rollouts.submit_for_approval(rollout)
      {:ok, _rollout} = Rollouts.approve_rollout(rollout, ctx.operator)

      approvals = Rollouts.list_approvals(rollout.id)
      assert length(approvals) == 1
      assert hd(approvals).user.email == ctx.operator.email
    end

    test "can_start_rollout? returns correct values" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      # Default is not_required
      assert Rollouts.can_start_rollout?(rollout)

      # After submitting for approval on a project that requires it
      project_with_approval =
        project_fixture(%{settings: %{"approval_required" => true}})

      bundle2 = compiled_bundle_fixture(%{project: project_with_approval})

      rollout2 =
        rollout_fixture(%{project: project_with_approval, bundle: bundle2})

      {:ok, rollout2} = Rollouts.submit_for_approval(rollout2)
      refute Rollouts.can_start_rollout?(rollout2)
    end
  end
end
