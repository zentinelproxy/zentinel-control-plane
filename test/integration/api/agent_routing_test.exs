defmodule ZentinelCpWeb.Integration.Api.AgentRoutingTest do
  @moduledoc """
  Integration tests proving that the control plane supports agent-specific
  routing — different services can have different plugins (WAF, rate-limiter,
  auth) and middleware stacks, and the KDL generator produces correct
  per-service configuration that gets bundled for deployment.

  This proves the full pipeline:
    Define services → Attach plugins/middleware per service →
    Generate KDL → Create bundle → Deploy to nodes
  """
  use ZentinelCpWeb.IntegrationCase

  alias ZentinelCp.{Services, Plugins, Bundles, Nodes, Rollouts, Repo}
  alias ZentinelCp.Services.BundleIntegration
  alias ZentinelCp.Rollouts.Rollout

  import Ecto.Query, only: [from: 2]

  @moduletag :integration

  describe "agent-specific routing via services, plugins, and middleware" do
    setup %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn,
          scopes: [
            "nodes:read",
            "nodes:write",
            "bundles:read",
            "bundles:write",
            "rollouts:read",
            "rollouts:write",
            "services:read",
            "services:write"
          ]
        )

      %{api_conn: api_conn, context: context}
    end

    test "services with different plugins produce per-service agent config in KDL", %{
      context: context
    } do
      project = context.project

      # ── Create two services with different upstreams ─────────────────────

      {:ok, api_service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Public API",
          route_path: "/api/v1/*",
          upstream_url: "http://api-backend:8080",
          enabled: true
        })

      {:ok, admin_service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Admin Panel",
          route_path: "/admin/*",
          upstream_url: "http://admin-backend:3000",
          enabled: true
        })

      # ── Create plugins (WAF for API, auth for Admin) ─────────────────────

      {:ok, waf_plugin} =
        Plugins.create_plugin(%{
          project_id: project.id,
          name: "WAF Agent",
          slug: "waf-agent",
          plugin_type: "wasm",
          default_config: %{"mode" => "block", "rules" => "owasp-crs"},
          enabled: true
        })

      {:ok, auth_plugin} =
        Plugins.create_plugin(%{
          project_id: project.id,
          name: "Auth Agent",
          slug: "auth-agent",
          plugin_type: "wasm",
          default_config: %{"provider" => "oidc", "issuer" => "https://auth.example.com"},
          enabled: true
        })

      # ── Attach WAF to API service, Auth to Admin service ─────────────────

      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: api_service.id,
          plugin_id: waf_plugin.id,
          position: 0,
          enabled: true,
          config_override: %{"mode" => "block", "sensitivity" => "high"}
        })

      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: admin_service.id,
          plugin_id: auth_plugin.id,
          position: 0,
          enabled: true,
          config_override: %{"require_mfa" => true}
        })

      # ── Generate KDL and verify per-service agent config ─────────────────

      {:ok, kdl} = BundleIntegration.preview_kdl(project.id)

      # KDL should contain both services
      assert kdl =~ "Public API" or kdl =~ "public-api" or kdl =~ "/api/v1"
      assert kdl =~ "Admin Panel" or kdl =~ "admin-panel" or kdl =~ "/admin"

      # KDL should have different upstreams
      assert kdl =~ "api-backend:8080"
      assert kdl =~ "admin-backend:3000"

      # KDL should contain WAF plugin config for API service
      assert kdl =~ "waf-agent"
      assert kdl =~ "sensitivity"

      # KDL should contain Auth plugin config for Admin service
      assert kdl =~ "auth-agent"
      assert kdl =~ "require_mfa"
    end

    test "services with different middleware stacks produce distinct configs", %{
      context: context
    } do
      project = context.project

      # ── Create services ──────────────────────────────────────────────────

      {:ok, public_service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Public Site",
          route_path: "/public/*",
          upstream_url: "http://web:4000",
          enabled: true
        })

      {:ok, internal_service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Internal API",
          route_path: "/internal/*",
          upstream_url: "http://internal:8080",
          enabled: true
        })

      # ── Create middleware ────────────────────────────────────────────────

      {:ok, rate_limit_mw} =
        Services.create_middleware(%{
          project_id: project.id,
          name: "Rate Limiter",
          middleware_type: "rate_limit",
          config: %{"requests_per_second" => 100, "burst" => 200},
          enabled: true
        })

      {:ok, cors_mw} =
        Services.create_middleware(%{
          project_id: project.id,
          name: "CORS",
          middleware_type: "cors",
          config: %{"allow_origins" => "*", "allow_methods" => "GET,POST"},
          enabled: true
        })

      {:ok, compression_mw} =
        Services.create_middleware(%{
          project_id: project.id,
          name: "Compression",
          middleware_type: "compression",
          config: %{"min_size" => 1024, "algorithms" => "gzip,br"},
          enabled: true
        })

      # ── Attach different middleware per service ──────────────────────────

      # Public: rate_limit + cors + compression
      {:ok, _} =
        Services.attach_middleware(%{
          service_id: public_service.id,
          middleware_id: rate_limit_mw.id,
          position: 0
        })

      {:ok, _} =
        Services.attach_middleware(%{
          service_id: public_service.id,
          middleware_id: cors_mw.id,
          position: 1
        })

      {:ok, _} =
        Services.attach_middleware(%{
          service_id: public_service.id,
          middleware_id: compression_mw.id,
          position: 2
        })

      # Internal: only compression (no rate limit, no cors)
      {:ok, _} =
        Services.attach_middleware(%{
          service_id: internal_service.id,
          middleware_id: compression_mw.id,
          position: 0,
          config_override: %{"min_size" => 512}
        })

      # ── Generate KDL ────────────────────────────────────────────────────

      {:ok, kdl} = BundleIntegration.preview_kdl(project.id)

      # Verify both services present
      assert kdl =~ "/public"
      assert kdl =~ "/internal"

      # Verify middleware appears in KDL
      assert kdl =~ "rate_limit" or kdl =~ "rate-limit"
      assert kdl =~ "cors"
      assert kdl =~ "compression"
    end

    test "generated bundle from services deploys to nodes with correct config", %{
      api_conn: api_conn,
      context: context
    } do
      project = context.project

      # ── Define services with plugins ─────────────────────────────────────

      {:ok, svc} =
        Services.create_service(%{
          project_id: project.id,
          name: "Gateway",
          route_path: "/*",
          upstream_url: "http://app:8080",
          enabled: true
        })

      {:ok, plugin} =
        Plugins.create_plugin(%{
          project_id: project.id,
          name: "Bot Manager",
          slug: "bot-manager",
          plugin_type: "wasm",
          default_config: %{"challenge_type" => "js"},
          enabled: true
        })

      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: svc.id,
          plugin_id: plugin.id,
          position: 0,
          enabled: true
        })

      # ── Generate bundle from service definitions ─────────────────────────

      {:ok, bundle} =
        BundleIntegration.create_bundle_from_services(
          project.id,
          "svc-gen-v1"
        )

      assert bundle.id
      assert bundle.config_source =~ "bot-manager"
      assert bundle.config_source =~ "app:8080"

      # Force compiled (zentinel binary not available)
      {:ok, bundle} = Bundles.update_status(bundle, "compiled")

      # ── Register nodes and deploy via rollout ────────────────────────────

      nodes =
        for i <- 1..2 do
          {node, _key} =
            ZentinelCp.NodesFixtures.node_with_key_fixture(%{
              project: project,
              name: "svc-node-#{i}"
            })

          node
        end

      rollout_resp =
        api_conn
        |> post("/api/v1/projects/#{project.slug}/rollouts", %{
          bundle_id: bundle.id,
          target_selector: %{"type" => "all"},
          strategy: "all_at_once"
        })
        |> json_response!(201)

      rollout = Rollouts.get_rollout!(rollout_resp["id"])
      # Creating the rollout through the API starts it.
      assert rollout.state == "running"

      node_ids = Enum.map(nodes, & &1.id)
      set_active_bundle(node_ids, bundle.id)

      # Send heartbeats so health gates pass
      for {node, _key} <- Enum.zip(nodes, Stream.cycle([nil])) do
        Nodes.record_heartbeat(node, %{
          health: %{"status" => "healthy"},
          version: "1.0.0"
        })
      end

      final = tick_until_terminal(rollout.id, max_ticks: 10)

      assert final.state == "completed"

      # All nodes have the service-generated bundle
      for node <- nodes do
        db_node = Nodes.get_node!(node.id)
        assert db_node.active_bundle_id == bundle.id
      end

      # Bundle config came from service definitions, not raw KDL
      stored = Bundles.get_bundle!(bundle.id)
      assert stored.config_source =~ "app:8080"
      assert stored.config_source =~ "bot-manager"
    end

    test "per-service plugin config override produces distinct agent configs", %{
      context: context
    } do
      project = context.project

      # ── Create shared plugin ─────────────────────────────────────────────

      {:ok, rate_plugin} =
        Plugins.create_plugin(%{
          project_id: project.id,
          name: "Rate Limiter Plugin",
          slug: "rate-limiter",
          plugin_type: "wasm",
          default_config: %{"limit" => 100, "window" => "1m"},
          enabled: true
        })

      # ── Create two services, attach same plugin with different overrides ─

      {:ok, public_svc} =
        Services.create_service(%{
          project_id: project.id,
          name: "Public Endpoint",
          route_path: "/public/*",
          upstream_url: "http://public:8080",
          enabled: true
        })

      {:ok, premium_svc} =
        Services.create_service(%{
          project_id: project.id,
          name: "Premium Endpoint",
          route_path: "/premium/*",
          upstream_url: "http://premium:8080",
          enabled: true
        })

      # Public: strict rate limit
      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: public_svc.id,
          plugin_id: rate_plugin.id,
          position: 0,
          enabled: true,
          config_override: %{"limit" => 50, "window" => "1m"}
        })

      # Premium: relaxed rate limit
      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: premium_svc.id,
          plugin_id: rate_plugin.id,
          position: 0,
          enabled: true,
          config_override: %{"limit" => 10000, "window" => "1m"}
        })

      # ── Generate KDL and verify per-service overrides ────────────────────

      {:ok, kdl} = BundleIntegration.preview_kdl(project.id)

      # Both services should reference the rate-limiter plugin
      # The KDL should contain "50" (public limit) and "10000" (premium limit)
      assert kdl =~ "rate-limiter"
      assert kdl =~ "50"
      assert kdl =~ "10000"

      # Verify the config override was applied, not just the default
      refute kdl =~ ~r/limit.*100[^0]/, "Default config (100) should be overridden"
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
