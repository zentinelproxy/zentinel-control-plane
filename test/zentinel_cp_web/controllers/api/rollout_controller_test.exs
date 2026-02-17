defmodule ZentinelCpWeb.Api.RolloutControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures
  import ZentinelCp.RolloutsFixtures

  alias ZentinelCp.Rollouts

  setup do
    project = project_fixture()
    {conn, _api_key} = authenticate_api(build_conn(), project: project)
    bundle = compiled_bundle_fixture(%{project: project})

    {:ok, conn: conn, project: project, bundle: bundle}
  end

  describe "POST /api/v1/projects/:slug/rollouts" do
    test "creates a rollout", %{conn: conn, project: project, bundle: bundle} do
      conn =
        post(conn, "/api/v1/projects/#{project.slug}/rollouts", %{
          "bundle_id" => bundle.id,
          "target_selector" => %{"type" => "all"},
          "strategy" => "rolling",
          "batch_size" => 2
        })

      assert %{"id" => id, "state" => "pending", "strategy" => "rolling"} =
               json_response(conn, 201)

      assert is_binary(id)
    end

    test "returns 404 for unknown project", %{conn: conn, bundle: bundle} do
      conn =
        post(conn, "/api/v1/projects/nonexistent/rollouts", %{
          "bundle_id" => bundle.id,
          "target_selector" => %{"type" => "all"}
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 409 for non-compiled bundle", %{conn: conn, project: project} do
      {:ok, pending_bundle} =
        ZentinelCp.Bundles.create_bundle(%{
          project_id: project.id,
          version: "uncompiled-#{System.unique_integer([:positive])}",
          config_source: "system {}"
        })

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/rollouts", %{
          "bundle_id" => pending_bundle.id,
          "target_selector" => %{"type" => "all"}
        })

      assert json_response(conn, 409)["error"] =~ "compiled"
    end

    test "returns 422 for invalid target selector", %{
      conn: conn,
      project: project,
      bundle: bundle
    } do
      conn =
        post(conn, "/api/v1/projects/#{project.slug}/rollouts", %{
          "bundle_id" => bundle.id,
          "target_selector" => %{"type" => "bogus"}
        })

      assert json_response(conn, 422)["error"]
    end
  end

  describe "GET /api/v1/projects/:slug/rollouts" do
    test "lists rollouts", %{conn: conn, project: project, bundle: bundle} do
      _r1 = rollout_fixture(%{project: project, bundle: bundle})
      _r2 = rollout_fixture(%{project: project, bundle: bundle})

      conn = get(conn, "/api/v1/projects/#{project.slug}/rollouts")

      assert %{"rollouts" => rollouts, "total" => 2} = json_response(conn, 200)
      assert length(rollouts) == 2
    end

    test "filters by state", %{conn: conn, project: project, bundle: bundle} do
      _rollout = rollout_fixture(%{project: project, bundle: bundle})

      conn = get(conn, "/api/v1/projects/#{project.slug}/rollouts?state=pending")
      assert %{"total" => 1} = json_response(conn, 200)

      conn = get(conn, "/api/v1/projects/#{project.slug}/rollouts?state=running")
      assert %{"total" => 0} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/projects/:slug/rollouts/:id" do
    test "shows rollout details", %{conn: conn, project: project, bundle: bundle} do
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      conn = get(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}")

      assert %{
               "rollout" => %{"id" => _, "state" => "pending"},
               "steps" => [],
               "progress" => %{"total" => 0}
             } = json_response(conn, 200)
    end

    test "returns 404 for unknown rollout", %{conn: conn, project: project} do
      conn = get(conn, "/api/v1/projects/#{project.slug}/rollouts/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/v1/projects/:slug/rollouts/:id/pause" do
    test "pauses a running rollout", %{conn: conn, project: project, bundle: bundle} do
      _node = node_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/pause")

      assert %{"state" => "paused"} = json_response(conn, 200)
    end

    test "returns 409 for non-running rollout", %{conn: conn, project: project, bundle: bundle} do
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/pause")
      assert json_response(conn, 409)["error"] =~ "cannot be paused"
    end
  end

  describe "POST /api/v1/projects/:slug/rollouts/:id/resume" do
    test "resumes a paused rollout", %{conn: conn, project: project, bundle: bundle} do
      _node = node_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      running = Rollouts.get_rollout!(rollout.id)
      {:ok, _paused} = Rollouts.pause_rollout(running)

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/resume")
      assert %{"state" => "running"} = json_response(conn, 200)
    end

    test "returns 409 for non-paused rollout", %{conn: conn, project: project, bundle: bundle} do
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/resume")
      assert json_response(conn, 409)["error"] =~ "cannot be resumed"
    end
  end

  describe "POST /api/v1/projects/:slug/rollouts/:id/cancel" do
    test "cancels a running rollout", %{conn: conn, project: project, bundle: bundle} do
      _node = node_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/cancel")
      assert %{"state" => "cancelled"} = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/projects/:slug/rollouts/:id/rollback" do
    test "rolls back a running rollout", %{conn: conn, project: project, bundle: bundle} do
      node = node_fixture(%{project: project})
      rollout = rollout_fixture(%{project: project, bundle: bundle})
      {:ok, _} = Rollouts.plan_rollout(rollout)

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/rollback")
      assert %{"state" => "cancelled"} = json_response(conn, 200)

      # Verify node staged_bundle_id was cleared
      updated_node = ZentinelCp.Nodes.get_node!(node.id)
      assert updated_node.staged_bundle_id == nil
    end

    test "returns 409 for completed rollout", %{conn: conn, project: project, bundle: bundle} do
      rollout = rollout_fixture(%{project: project, bundle: bundle})

      # Force to completed
      rollout
      |> ZentinelCp.Rollouts.Rollout.state_changeset("completed")
      |> ZentinelCp.Repo.update!()

      conn = post(conn, "/api/v1/projects/#{project.slug}/rollouts/#{rollout.id}/rollback")
      assert json_response(conn, 409)["error"] =~ "cannot be rolled back"
    end
  end
end
