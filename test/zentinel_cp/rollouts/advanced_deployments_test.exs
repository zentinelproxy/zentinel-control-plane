defmodule ZentinelCp.Rollouts.AdvancedDeploymentsTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Rollouts
  alias ZentinelCp.Rollouts.{CanaryAnalysis, FreezeWindow}
  alias ZentinelCp.Projects.PromotionRule

  import ZentinelCp.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  describe "blue-green strategy" do
    test "allows blue_green as a valid strategy", %{project: project} do
      bundle = bundle_fixture(%{project_id: project.id})

      attrs = %{
        project_id: project.id,
        bundle_id: bundle.id,
        target_selector: %{"type" => "all"},
        strategy: "blue_green",
        deployment_slot: "green",
        validation_period_seconds: 600
      }

      changeset =
        ZentinelCp.Rollouts.Rollout.create_changeset(%ZentinelCp.Rollouts.Rollout{}, attrs)

      assert changeset.valid?
    end

    test "allows canary as a valid strategy", %{project: project} do
      bundle = bundle_fixture(%{project_id: project.id})

      attrs = %{
        project_id: project.id,
        bundle_id: bundle.id,
        target_selector: %{"type" => "all"},
        strategy: "canary",
        canary_analysis_config: %{
          "error_rate_threshold" => 5.0,
          "steps" => [5, 25, 50, 100]
        }
      }

      changeset =
        ZentinelCp.Rollouts.Rollout.create_changeset(%ZentinelCp.Rollouts.Rollout{}, attrs)

      assert changeset.valid?
    end
  end

  describe "canary analysis" do
    test "returns default config" do
      config = CanaryAnalysis.default_config()
      assert config["error_rate_threshold"] == 5.0
      assert config["steps"] == [5, 25, 50, 100]
    end

    test "current_step_percentage returns correct values" do
      config = CanaryAnalysis.default_config()
      assert CanaryAnalysis.current_step_percentage(config, 0) == 5
      assert CanaryAnalysis.current_step_percentage(config, 1) == 25
      assert CanaryAnalysis.current_step_percentage(config, 2) == 50
      assert CanaryAnalysis.current_step_percentage(config, 3) == 100
    end

    test "next_step? returns true for intermediate steps" do
      config = CanaryAnalysis.default_config()
      assert CanaryAnalysis.next_step?(config, 0) == true
      assert CanaryAnalysis.next_step?(config, 1) == true
      assert CanaryAnalysis.next_step?(config, 2) == true
      assert CanaryAnalysis.next_step?(config, 3) == false
    end

    test "analyze returns :extend when no data" do
      rollout = %{canary_analysis_config: CanaryAnalysis.default_config()}
      {decision, result} = CanaryAnalysis.analyze(rollout, ["fake-node-1"], ["fake-node-2"])
      assert decision == :extend
      assert result.canary.total_requests == 0
    end
  end

  describe "freeze windows" do
    test "creates a freeze window", %{project: project} do
      now = DateTime.utc_now()

      attrs = %{
        project_id: project.id,
        name: "Holiday Freeze",
        starts_at: DateTime.add(now, -3600, :second),
        ends_at: DateTime.add(now, 3600, :second),
        reason: "Holiday code freeze"
      }

      changeset = FreezeWindow.changeset(%FreezeWindow{}, attrs)
      assert changeset.valid?
    end

    test "validates end after start" do
      now = DateTime.utc_now()

      attrs = %{
        project_id: Ecto.UUID.generate(),
        name: "Bad Window",
        starts_at: DateTime.add(now, 3600, :second),
        ends_at: DateTime.add(now, -3600, :second)
      }

      changeset = FreezeWindow.changeset(%FreezeWindow{}, attrs)
      assert "must be after starts_at" in errors_on(changeset).ends_at
    end

    test "active? returns true during freeze" do
      now = DateTime.utc_now()

      window = %FreezeWindow{
        starts_at: DateTime.add(now, -3600, :second),
        ends_at: DateTime.add(now, 3600, :second)
      }

      assert FreezeWindow.active?(window)
    end

    test "active? returns false outside freeze" do
      now = DateTime.utc_now()

      window = %FreezeWindow{
        starts_at: DateTime.add(now, -7200, :second),
        ends_at: DateTime.add(now, -3600, :second)
      }

      refute FreezeWindow.active?(window)
    end

    test "freeze window blocks rollout creation", %{project: project} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _window} =
        %FreezeWindow{}
        |> FreezeWindow.changeset(%{
          project_id: project.id,
          name: "Active Freeze",
          starts_at: DateTime.add(now, -3600, :second),
          ends_at: DateTime.add(now, 3600, :second)
        })
        |> Repo.insert()

      bundle = bundle_fixture(%{project_id: project.id})

      result =
        Rollouts.create_rollout(%{
          project_id: project.id,
          bundle_id: bundle.id,
          target_selector: %{"type" => "all"},
          strategy: "rolling"
        })

      assert {:error, {:freeze_window_active, _}} = result
    end

    test "freeze window can be overridden", %{project: project} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _window} =
        %FreezeWindow{}
        |> FreezeWindow.changeset(%{
          project_id: project.id,
          name: "Override Freeze",
          starts_at: DateTime.add(now, -3600, :second),
          ends_at: DateTime.add(now, 3600, :second)
        })
        |> Repo.insert()

      bundle = bundle_fixture(%{project_id: project.id})

      result =
        Rollouts.create_rollout(
          %{
            project_id: project.id,
            bundle_id: bundle.id,
            target_selector: %{"type" => "all"},
            strategy: "rolling"
          },
          override_freeze: true
        )

      # Should not be blocked by freeze (may fail for other reasons like bundle not compiled)
      refute match?({:error, {:freeze_window_active, _}}, result)
    end
  end

  describe "promotion rules" do
    test "creates a promotion rule", %{project: project} do
      env1 = environment_fixture(%{project_id: project.id, name: "staging"})
      env2 = environment_fixture(%{project_id: project.id, name: "production"})

      changeset =
        PromotionRule.changeset(%PromotionRule{}, %{
          project_id: project.id,
          source_env_id: env1.id,
          target_env_id: env2.id,
          auto_promote: true,
          delay_minutes: 30
        })

      assert changeset.valid?
    end

    test "validates different environments" do
      env_id = Ecto.UUID.generate()

      changeset =
        PromotionRule.changeset(%PromotionRule{}, %{
          project_id: Ecto.UUID.generate(),
          source_env_id: env_id,
          target_env_id: env_id,
          auto_promote: true
        })

      assert "must be different from source environment" in errors_on(changeset).target_env_id
    end
  end

  # Helper to create a bundle fixture
  defp bundle_fixture(attrs) do
    {:ok, bundle} =
      ZentinelCp.Bundles.create_bundle(%{
        project_id: attrs[:project_id],
        version: "test-#{System.unique_integer([:positive])}",
        config_source: "test config",
        source_type: "api"
      })

    bundle
  end

  defp environment_fixture(attrs) do
    name = attrs[:name] || "test-env-#{System.unique_integer([:positive])}"

    {:ok, env} =
      %ZentinelCp.Projects.Environment{}
      |> ZentinelCp.Projects.Environment.create_changeset(%{
        project_id: attrs[:project_id],
        name: name
      })
      |> Repo.insert()

    env
  end
end
