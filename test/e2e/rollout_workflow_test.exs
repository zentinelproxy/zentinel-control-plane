defmodule ZentinelCpWeb.E2E.RolloutWorkflowTest do
  @moduledoc """
  E2E tests for rollout management UI.

  Tests progress display, pause/resume, and cancel operations.
  """
  use ZentinelCpWeb.FeatureCase

  alias ZentinelCp.Rollouts.Rollout

  @moduletag :e2e

  import Wallaby.Query

  # Helper to force rollout state for testing
  defp force_rollout_state(rollout, state) do
    rollout
    |> Rollout.state_changeset(state)
    |> ZentinelCp.Repo.update()
  end

  describe "rollouts list page" do
    feature "shows empty state when no rollouts", %{session: session} do
      {session, context} = setup_full_context(session)

      session
      |> visit("/projects/#{context.project.slug}/rollouts")
      |> assert_has(css("h1", text: "Rollouts"))
    end

    feature "displays rollouts when they exist", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})
      ZentinelCp.RolloutsFixtures.rollout_fixture(%{project: context.project, bundle: bundle})

      session
      |> visit("/projects/#{context.project.slug}/rollouts")
      |> assert_has(css("table"))
      |> assert_has(css("[data-testid='rollout-state']"))
    end
  end

  describe "rollout details" do
    feature "view rollout details with progress", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context.project,
          version: "rollout-v1"
        })

      # Create some nodes
      for i <- 1..3 do
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "rollout-node-#{i}"
        })
      end

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      session
      |> visit("/projects/#{context.project.slug}/rollouts/#{rollout.id}")
      |> assert_has(css("h1"))
      |> assert_has(css("[data-testid='rollout-progress']"))
      |> assert_has(css("[data-testid='rollout-state']"))
    end

    feature "shows rollout steps", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "step-node-1"})
      ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "step-node-2"})

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle,
          batch_size: 1
        })

      session
      |> visit("/projects/#{context.project.slug}/rollouts/#{rollout.id}")
      |> assert_has(css("[data-testid='rollout-steps']"))
    end
  end

  describe "rollout control actions" do
    feature "pause running rollout", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      # Force to running state
      {:ok, _} = force_rollout_state(rollout, "running")

      session
      |> visit("/projects/#{context.project.slug}/rollouts/#{rollout.id}")
      |> assert_has(css("button[phx-click='pause']"))
      |> click(css("button[phx-click='pause']"))
      |> assert_has(css("[data-testid='rollout-state']", text: "paused"))
    end

    feature "resume paused rollout", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      # Force to paused state
      {:ok, _} = force_rollout_state(rollout, "paused")

      session
      |> visit("/projects/#{context.project.slug}/rollouts/#{rollout.id}")
      |> assert_has(css("button[phx-click='resume']"))
      |> click(css("button[phx-click='resume']"))
      |> assert_has(css("[data-testid='rollout-state']", text: "running"))
    end

    feature "cancel rollout", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      rollout =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      # Force to running state
      {:ok, _} = force_rollout_state(rollout, "running")

      session
      |> visit("/projects/#{context.project.slug}/rollouts/#{rollout.id}")
      |> assert_has(css("button[phx-click='cancel']"))
      |> click(css("button[phx-click='cancel']"))
      |> assert_has(css("[data-testid='rollout-state']", text: "cancelled"))
    end
  end

  describe "rollout filtering" do
    feature "filter rollouts by state", %{session: session} do
      {session, context} = setup_full_context(session)

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Create rollouts in different states
      _pending =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      running =
        ZentinelCp.RolloutsFixtures.rollout_fixture(%{
          project: context.project,
          bundle: bundle
        })

      {:ok, _} = force_rollout_state(running, "running")

      session
      |> visit("/projects/#{context.project.slug}/rollouts")
      |> assert_has(css("[data-testid='rollout-row']", count: 2))
    end
  end
end
