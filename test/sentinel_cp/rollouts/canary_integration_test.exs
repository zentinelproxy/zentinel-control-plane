defmodule SentinelCp.Rollouts.CanaryIntegrationTest do
  use SentinelCp.DataCase

  alias SentinelCp.Rollouts
  alias SentinelCp.Rollouts.{Rollout, CanaryAnalysis}

  import SentinelCp.ProjectsFixtures
  import SentinelCp.NodesFixtures
  import SentinelCp.RolloutsFixtures

  describe "canary batch planning" do
    test "creates canary batches based on first step percentage" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      # Create 20 nodes
      _nodes = for _ <- 1..20, do: node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "canary",
          canary_analysis_config: %{
            "steps" => [5, 25, 50, 100],
            "error_rate_threshold" => 5.0,
            "latency_p99_threshold_ms" => 500,
            "analysis_window_minutes" => 5
          }
        })

      {:ok, {updated, _steps}} = Rollouts.plan_rollout(rollout)

      assert updated.state == "running"
      assert updated.canary_step_index == 0

      # Check steps: first step should have ~5% of 20 = 1 node
      rollout_with_steps = Rollouts.get_rollout_with_details(updated.id)
      steps = rollout_with_steps.steps

      assert length(steps) == 2
      # First step: canary batch (5% of 20 = 1 node)
      first_step = Enum.find(steps, &(&1.step_index == 0))
      assert length(first_step.node_ids) == 1

      # Second step: remaining nodes
      second_step = Enum.find(steps, &(&1.step_index == 1))
      assert length(second_step.node_ids) == 19
    end

    test "creates single batch when canary percentage covers all nodes" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      _node = node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "canary",
          canary_analysis_config: %{"steps" => [100]}
        })

      {:ok, {_updated, _steps}} = Rollouts.plan_rollout(rollout)

      rollout_with_steps = Rollouts.get_rollout_with_details(rollout.id)
      assert length(rollout_with_steps.steps) == 1
    end

    test "uses default config when canary_analysis_config is nil" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      for _ <- 1..20, do: node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "canary"
        })

      {:ok, {updated, _steps}} = Rollouts.plan_rollout(rollout)
      assert updated.state == "running"

      rollout_with_steps = Rollouts.get_rollout_with_details(updated.id)
      assert length(rollout_with_steps.steps) == 2
    end
  end

  describe "canary analysis module" do
    test "current_step_percentage returns correct percentage" do
      config = %{"steps" => [5, 25, 50, 100]}
      assert CanaryAnalysis.current_step_percentage(config, 0) == 5
      assert CanaryAnalysis.current_step_percentage(config, 1) == 25
      assert CanaryAnalysis.current_step_percentage(config, 2) == 50
      assert CanaryAnalysis.current_step_percentage(config, 3) == 100
      # Out of bounds returns 100
      assert CanaryAnalysis.current_step_percentage(config, 10) == 100
    end

    test "next_step? returns true when more steps exist" do
      config = %{"steps" => [5, 25, 50, 100]}
      assert CanaryAnalysis.next_step?(config, 0)
      assert CanaryAnalysis.next_step?(config, 1)
      assert CanaryAnalysis.next_step?(config, 2)
      refute CanaryAnalysis.next_step?(config, 3)
    end

    test "default_config returns expected values" do
      config = CanaryAnalysis.default_config()
      assert config["error_rate_threshold"] == 5.0
      assert config["latency_p99_threshold_ms"] == 500
      assert config["steps"] == [5, 25, 50, 100]
    end
  end

  describe "canary tick loop integration" do
    test "extend decision keeps rollout in same state" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})
      for _ <- 1..10, do: node_fixture(%{project: project})

      rollout =
        rollout_fixture(%{
          project: project,
          bundle: bundle,
          strategy: "canary",
          health_gates: %{},
          canary_analysis_config: %{
            "steps" => [10, 50, 100],
            "error_rate_threshold" => 5.0,
            "latency_p99_threshold_ms" => 500,
            "analysis_window_minutes" => 5
          }
        })

      {:ok, {updated, _steps}} = Rollouts.plan_rollout(rollout)

      # Tick the rollout — should start first step
      {:ok, result} = Rollouts.tick_rollout(Rollouts.get_rollout!(updated.id))
      assert result == :step_started

      # Simulate nodes activating the bundle for step 0
      rollout_detail = Rollouts.get_rollout_with_details(updated.id)
      first_step = Enum.find(rollout_detail.steps, &(&1.step_index == 0))

      for node_id <- first_step.node_ids do
        SentinelCp.Nodes.Node
        |> SentinelCp.Repo.get!(node_id)
        |> Ecto.Changeset.change(%{active_bundle_id: bundle.id})
        |> SentinelCp.Repo.update!()
      end

      # Tick again — should transition to verifying
      {:ok, result2} = Rollouts.tick_rollout(Rollouts.get_rollout!(updated.id))
      assert result2 == :step_verifying

      # Tick again — canary analysis should run, no traffic data = extend
      {:ok, result3} = Rollouts.tick_rollout(Rollouts.get_rollout!(updated.id))
      assert result3 == :canary_extend

      # Rollout should still be running
      rollout_reloaded = Rollouts.get_rollout!(updated.id)
      assert rollout_reloaded.state == "running"
    end
  end

  describe "rollout schema canary fields" do
    test "canary strategy is valid" do
      project = project_fixture()
      bundle = compiled_bundle_fixture(%{project: project})

      {:ok, %Rollout{} = rollout} =
        Rollouts.create_rollout(%{
          project_id: project.id,
          bundle_id: bundle.id,
          target_selector: %{"type" => "all"},
          strategy: "canary",
          canary_analysis_config: %{
            "steps" => [10, 50, 100],
            "error_rate_threshold" => 3.0
          }
        })

      assert rollout.strategy == "canary"
      assert rollout.canary_analysis_config["steps"] == [10, 50, 100]
      assert rollout.canary_step_index == 0
    end
  end
end
