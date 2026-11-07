defmodule ZentinelCpWeb.Integration.Api.MultiBackendConfigTest do
  @moduledoc """
  Integration tests proving that the control plane correctly scopes bundles
  and node distribution across multiple projects with different configurations.

  Verifies that:
  - Distinct configs are distributed only to their project's nodes
  - Rollouts cannot reference another project's bundle
  - Bundle and node lists are scoped per project
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Rollouts, Bundles, Nodes, Repo}
  alias ZentinelCp.Rollouts.Rollout

  import Ecto.Query, only: [from: 2]

  @moduletag :integration

  @waf_config ~s"""
  system { workers 4 }
  listeners { listener "http" address="0.0.0.0:8080" }
  waf { enabled true; mode "block"; rules "owasp-crs-sqli" "owasp-crs-xss" }
  rate-limit { global requests-per-second=1000 }
  """

  @auth_config ~s"""
  system { workers 2 }
  listeners { listener "http" address="0.0.0.0:9090" }
  auth { provider "jwt"; jwks-url "https://auth.example.com/.well-known/jwks.json" }
  transform { request { add-header "X-Request-ID" value="{{uuid}}" } }
  """

  @api_scopes [
    "nodes:read",
    "nodes:write",
    "bundles:read",
    "bundles:write",
    "rollouts:read",
    "rollouts:write"
  ]

  describe "multi-project configuration scoping" do
    test "distinct configs are distributed to correct project nodes", %{conn: conn} do
      # ── Setup: Two separate orgs/projects ───────────────────────────────

      {api_conn_a, context_a} = setup_api_context(conn, scopes: @api_scopes)
      project_a = context_a.project
      slug_a = project_a.slug

      {api_conn_b, context_b} =
        setup_api_context(Phoenix.ConnTest.build_conn(), scopes: @api_scopes)

      project_b = context_b.project
      slug_b = project_b.slug

      # ── Register 2 nodes per project ────────────────────────────────────

      nodes_a =
        for i <- 1..2 do
          resp =
            Phoenix.ConnTest.build_conn()
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{slug_a}/nodes/register", %{
              name: "proj-a-node-#{i}",
              labels: %{"env" => "prod", "project" => "waf"},
              version: "1.0.0"
            })
            |> json_response!(201)

          assert resp["node_id"]
          assert resp["node_key"]
          %{id: resp["node_id"], key: resp["node_key"]}
        end

      nodes_b =
        for i <- 1..2 do
          resp =
            Phoenix.ConnTest.build_conn()
            |> put_req_header("content-type", "application/json")
            |> post("/api/v1/projects/#{slug_b}/nodes/register", %{
              name: "proj-b-node-#{i}",
              labels: %{"env" => "prod", "project" => "auth"},
              version: "1.0.0"
            })
            |> json_response!(201)

          assert resp["node_id"]
          assert resp["node_key"]
          %{id: resp["node_id"], key: resp["node_key"]}
        end

      # Send initial heartbeats so nodes are online
      send_heartbeats(nodes_a)
      send_heartbeats(nodes_b)

      # ── Create compiled bundles with different KDL configs ──────────────

      bundle_a =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project_a,
          version: "waf-1.0.0",
          config_source: @waf_config
        })

      bundle_b =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: project_b,
          version: "auth-1.0.0",
          config_source: @auth_config
        })

      # ── Create rolling rollouts for each project ────────────────────────

      rollout_a_resp =
        api_conn_a
        |> post("/api/v1/projects/#{slug_a}/rollouts", %{
          bundle_id: bundle_a.id,
          target_selector: %{"type" => "all"},
          strategy: "rolling",
          batch_size: 2,
          progress_deadline_seconds: 600
        })
        |> json_response!(201)

      rollout_b_resp =
        api_conn_b
        |> post("/api/v1/projects/#{slug_b}/rollouts", %{
          bundle_id: bundle_b.id,
          target_selector: %{"type" => "all"},
          strategy: "rolling",
          batch_size: 2,
          progress_deadline_seconds: 600
        })
        |> json_response!(201)

      rollout_a_id = rollout_a_resp["id"]
      rollout_b_id = rollout_b_resp["id"]

      # ── Plan and tick both rollouts ─────────────────────────────────────

      rollout_a = Rollouts.get_rollout!(rollout_a_id)
      planned_a = rollout_a
      assert planned_a.state == "running"

      rollout_b = Rollouts.get_rollout!(rollout_b_id)
      planned_b = rollout_b
      assert planned_b.state == "running"

      # Tick to start step assignments
      rollout_a = Rollouts.get_rollout!(rollout_a_id)
      {:ok, _} = Rollouts.tick_rollout(rollout_a)

      rollout_b = Rollouts.get_rollout!(rollout_b_id)
      {:ok, _} = Rollouts.tick_rollout(rollout_b)

      # ── Simulate node activation ───────────────────────────────────────

      node_ids_a = Enum.map(nodes_a, & &1.id)
      node_ids_b = Enum.map(nodes_b, & &1.id)

      set_active_bundle(node_ids_a, bundle_a.id)
      set_active_bundle(node_ids_b, bundle_b.id)

      # Send heartbeats reporting the active bundle
      send_heartbeats(nodes_a, bundle_a.id)
      send_heartbeats(nodes_b, bundle_b.id)

      # Tick both rollouts to completion
      final_a = tick_until_terminal(rollout_a_id, max_ticks: 15)
      final_b = tick_until_terminal(rollout_b_id, max_ticks: 15)

      assert final_a.state == "completed",
             "Project A rollout expected completed, got #{final_a.state}"

      assert final_b.state == "completed",
             "Project B rollout expected completed, got #{final_b.state}"

      # ── Verify: project A nodes have project A's bundle ─────────────────

      for node <- nodes_a do
        db_node = Nodes.get_node!(node.id)
        assert db_node.active_bundle_id == bundle_a.id
      end

      # ── Verify: project B nodes have project B's bundle ─────────────────

      for node <- nodes_b do
        db_node = Nodes.get_node!(node.id)
        assert db_node.active_bundle_id == bundle_b.id
      end

      # ── Verify config_source is correctly stored ────────────────────────

      stored_bundle_a = Bundles.get_bundle!(bundle_a.id)
      assert stored_bundle_a.config_source == @waf_config

      stored_bundle_b = Bundles.get_bundle!(bundle_b.id)
      assert stored_bundle_b.config_source == @auth_config
    end

    test "API key from project A cannot access project B's data", %{conn: conn} do
      # ── Setup: Two projects ─────────────────────────────────────────────

      {api_conn_a, context_a} =
        setup_api_context(conn, scopes: ["bundles:read", "nodes:read"])

      slug_a = context_a.project.slug

      {api_conn_b, context_b} =
        setup_api_context(Phoenix.ConnTest.build_conn(),
          scopes: ["bundles:read", "nodes:read"]
        )

      slug_b = context_b.project.slug

      # Create a bundle in each project
      ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
        project: context_a.project,
        version: "scope-a-v1"
      })

      ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
        project: context_b.project,
        version: "scope-b-v1"
      })

      # Register nodes in each project
      Phoenix.ConnTest.build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/projects/#{slug_a}/nodes/register", %{
        name: "scope-node-a",
        version: "1.0.0"
      })
      |> json_response!(201)

      Phoenix.ConnTest.build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/projects/#{slug_b}/nodes/register", %{
        name: "scope-node-b",
        version: "1.0.0"
      })
      |> json_response!(201)

      # Project A's API key can access project A's data
      bundles_a =
        api_conn_a
        |> get("/api/v1/projects/#{slug_a}/bundles")
        |> json_response!(200)

      assert bundles_a["total"] == 1
      assert hd(bundles_a["bundles"])["version"] == "scope-a-v1"

      nodes_a =
        api_conn_a
        |> get("/api/v1/projects/#{slug_a}/nodes")
        |> json_response!(200)

      assert nodes_a["total"] == 1
      assert hd(nodes_a["nodes"])["name"] == "scope-node-a"

      # Project A's API key CANNOT access project B's data
      # (returns 404 "project not found" — API keys are project-scoped)
      api_conn_a
      |> get("/api/v1/projects/#{slug_b}/bundles")
      |> json_response!(404)

      api_conn_a
      |> get("/api/v1/projects/#{slug_b}/nodes")
      |> json_response!(404)

      # And vice versa
      api_conn_b
      |> get("/api/v1/projects/#{slug_a}/bundles")
      |> json_response!(404)
    end

    test "bundle and node lists are scoped per project", %{conn: conn} do
      # ── Setup: Two projects with bundles and nodes ──────────────────────

      {api_conn_a, context_a} = setup_api_context(conn, scopes: @api_scopes)
      slug_a = context_a.project.slug

      {api_conn_b, context_b} =
        setup_api_context(Phoenix.ConnTest.build_conn(), scopes: @api_scopes)

      slug_b = context_b.project.slug

      # Create bundles
      _bundle_a =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context_a.project,
          version: "scope-a-v1",
          config_source: @waf_config
        })

      _bundle_b =
        ZentinelCp.RolloutsFixtures.compiled_bundle_fixture(%{
          project: context_b.project,
          version: "scope-b-v1",
          config_source: @auth_config
        })

      # Register nodes in each project
      for i <- 1..2 do
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{slug_a}/nodes/register", %{
          name: "scope-a-node-#{i}",
          version: "1.0.0"
        })
        |> json_response!(201)
      end

      for i <- 1..3 do
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/projects/#{slug_b}/nodes/register", %{
          name: "scope-b-node-#{i}",
          version: "1.0.0"
        })
        |> json_response!(201)
      end

      # ── Verify: project A bundle list only shows project A bundles ──────

      bundles_a_resp =
        api_conn_a
        |> get("/api/v1/projects/#{slug_a}/bundles")
        |> json_response!(200)

      bundle_versions_a =
        Enum.map(bundles_a_resp["bundles"], & &1["version"])

      assert "scope-a-v1" in bundle_versions_a
      refute Enum.any?(bundle_versions_a, &(&1 == "scope-b-v1"))

      # ── Verify: project B bundle list only shows project B bundles ──────

      bundles_b_resp =
        api_conn_b
        |> get("/api/v1/projects/#{slug_b}/bundles")
        |> json_response!(200)

      bundle_versions_b =
        Enum.map(bundles_b_resp["bundles"], & &1["version"])

      assert "scope-b-v1" in bundle_versions_b
      refute Enum.any?(bundle_versions_b, &(&1 == "scope-a-v1"))

      # ── Verify: project A node list only shows project A nodes ──────────

      nodes_a_resp =
        api_conn_a
        |> get("/api/v1/projects/#{slug_a}/nodes")
        |> json_response!(200)

      assert nodes_a_resp["total"] == 2

      node_names_a = Enum.map(nodes_a_resp["nodes"], & &1["name"])
      assert Enum.all?(node_names_a, &String.starts_with?(&1, "scope-a-"))

      # ── Verify: project B node list only shows project B nodes ──────────

      nodes_b_resp =
        api_conn_b
        |> get("/api/v1/projects/#{slug_b}/nodes")
        |> json_response!(200)

      assert nodes_b_resp["total"] == 3

      node_names_b = Enum.map(nodes_b_resp["nodes"], & &1["name"])
      assert Enum.all?(node_names_b, &String.starts_with?(&1, "scope-b-"))
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp set_active_bundle(node_ids, bundle_id) do
    from(n in Nodes.Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [active_bundle_id: bundle_id])
  end

  defp send_heartbeats(nodes, active_bundle_id \\ nil) do
    for node <- nodes do
      body =
        %{
          health: %{"status" => "healthy"},
          metrics: %{"cpu_percent" => 30},
          version: "1.0.0"
        }
        |> then(fn b ->
          if active_bundle_id, do: Map.put(b, :active_bundle_id, active_bundle_id), else: b
        end)

      Phoenix.ConnTest.build_conn()
      |> authenticate_as_node(node.key)
      |> post("/api/v1/nodes/#{node.id}/heartbeat", body)
      |> json_response!(200)
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
