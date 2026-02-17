defmodule ZentinelCpWeb.Integration.Api.RolloutLifecycleTest do
  @moduledoc """
  Integration tests for rollout API workflows.

  Tests the complete lifecycle: create → plan → pause → resume → cancel
  Also tests rollback functionality.
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.Rollouts.Rollout

  @moduletag :integration

  # Helper to force rollout state for testing (bypasses state machine guards)
  defp force_rollout_state(rollout, state) do
    rollout
    |> Rollout.state_changeset(state)
    |> ZentinelCp.Repo.update()
  end

  describe "rollout creation" do
    test "create rollout for compiled bundle", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write", "bundles:read"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Create some nodes for the rollout to target
      for i <- 1..3 do
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "rollout-node-#{i}"
        })
      end

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id,
          target_selector: %{"type" => "all"},
          strategy: "rolling",
          batch_size: 1,
          progress_deadline_seconds: 600
        })
        |> json_response!(201)

      assert create_resp["id"]
      assert create_resp["bundle_id"] == bundle.id
      assert create_resp["strategy"] == "rolling"
      assert create_resp["state"] in ["pending", "running"]
    end

    test "cannot create rollout for non-compiled bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:write", "bundles:write"])

      # Create a pending bundle
      {:ok, bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: context.project.id,
          version: "pending-rollout-v1",
          config_source: "system { workers 1 }"
        })

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id
        })
        |> json_response!(409)

      assert error_resp["error"] =~ "compiled"
    end

    test "cannot create rollout for non-existent bundle", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:write"])

      fake_id = Ecto.UUID.generate()

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: fake_id
        })
        |> json_response!(404)

      assert error_resp["error"] =~ "Bundle not found"
    end
  end

  describe "rollout state transitions" do
    setup %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Create nodes
      for i <- 1..2 do
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "state-node-#{i}"
        })
      end

      # Create rollout
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id,
          strategy: "rolling",
          batch_size: 1
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      %{api_conn: api_conn, context: context, rollout_id: rollout_id}
    end

    test "pause running rollout", %{api_conn: api_conn, context: context, rollout_id: rollout_id} do
      # Force to running state for test
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "running")

      pause_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/pause")
        |> json_response!(200)

      assert pause_resp["state"] == "paused"
    end

    test "resume paused rollout", %{api_conn: api_conn, context: context, rollout_id: rollout_id} do
      # Force to paused state
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "paused")

      resume_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/resume")
        |> json_response!(200)

      assert resume_resp["state"] == "running"
    end

    test "cancel rollout", %{api_conn: api_conn, context: context, rollout_id: rollout_id} do
      # Force to running state
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "running")

      cancel_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/cancel")
        |> json_response!(200)

      assert cancel_resp["state"] == "cancelled"
    end

    test "cannot pause already paused rollout", %{
      api_conn: api_conn,
      context: context,
      rollout_id: rollout_id
    } do
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "paused")

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/pause")
        |> json_response!(409)

      assert error_resp["error"] =~ "cannot be paused"
    end

    test "cannot resume running rollout", %{
      api_conn: api_conn,
      context: context,
      rollout_id: rollout_id
    } do
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "running")

      error_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/resume")
        |> json_response!(409)

      assert error_resp["error"] =~ "cannot be resumed"
    end
  end

  describe "rollout listing and details" do
    test "list rollouts with state filter", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      # Create a rollout
      api_conn
      |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
        bundle_id: bundle.id
      })
      |> json_response!(201)

      # List all
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts")
        |> json_response!(200)

      assert list_resp["total"] >= 1

      # Filter by state
      pending_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts?state=pending")
        |> json_response!(200)

      assert Enum.all?(pending_resp["rollouts"], &(&1["state"] == "pending"))
    end

    test "show rollout with steps and progress", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      ZentinelCp.NodesFixtures.node_fixture(%{project: context.project, name: "progress-node"})

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      show_resp =
        api_conn
        |> get("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}")
        |> json_response!(200)

      assert show_resp["rollout"]["id"] == rollout_id
      assert is_list(show_resp["steps"])
      assert is_map(show_resp["progress"])
    end
  end

  describe "rollback" do
    test "rollback running rollout", %{conn: conn} do
      {api_conn, context} = setup_api_context(conn, scopes: ["rollouts:read", "rollouts:write"])

      bundle = ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{project: context.project})

      create_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts", %{
          bundle_id: bundle.id
        })
        |> json_response!(201)

      rollout_id = create_resp["id"]

      # Force to running state
      rollout = ZentinelCp.Rollouts.get_rollout(rollout_id)
      {:ok, _} = force_rollout_state(rollout, "running")

      rollback_resp =
        api_conn
        |> post("/api/v1/projects/#{context.project.slug}/rollouts/#{rollout_id}/rollback")
        |> json_response!(200)

      # Rollback cancels the current rollout and reverts nodes
      assert rollback_resp["state"] == "cancelled"
    end
  end
end
