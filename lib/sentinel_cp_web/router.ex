defmodule SentinelCpWeb.Router do
  use SentinelCpWeb, :router

  import SentinelCpWeb.Plugs.Auth,
    only: [
      fetch_current_user: 2,
      require_authenticated_user: 2,
      redirect_if_user_is_authenticated: 2
    ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelCpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :node_auth do
    plug SentinelCpWeb.Plugs.NodeAuth
  end

  pipeline :api_auth do
    plug SentinelCpWeb.Plugs.ApiAuth
  end

  # Scope-specific pipelines
  pipeline :require_nodes_read do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "nodes:read"
  end

  pipeline :require_nodes_write do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "nodes:write"
  end

  pipeline :require_bundles_read do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "bundles:read"
  end

  pipeline :require_bundles_write do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "bundles:write"
  end

  pipeline :require_rollouts_read do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "rollouts:read"
  end

  pipeline :require_rollouts_write do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "rollouts:write"
  end

  pipeline :require_services_read do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "services:read"
  end

  pipeline :require_services_write do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "services:write"
  end

  pipeline :require_api_keys_admin do
    plug SentinelCpWeb.Plugs.RequireScope, scope: "api_keys:admin"
  end

  # Health checks (no auth, no session)
  scope "/", SentinelCpWeb do
    pipe_through :api

    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
  end

  # API Documentation (public, no auth)
  scope "/api", SentinelCpWeb do
    pipe_through :browser

    get "/docs", ApiDocsController, :index
  end

  # Prometheus metrics
  scope "/" do
    pipe_through :api

    get "/metrics", SentinelCpWeb.PromExPlug, prom_ex_module: SentinelCp.PromEx
  end

  # Auth routes (no login required)
  scope "/", SentinelCpWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live "/login", AuthLive.Login, :login
  end

  # Session management
  scope "/", SentinelCpWeb do
    pipe_through [:browser]

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  # Browser routes (login required)
  scope "/", SentinelCpWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home

    # Org management
    live "/orgs", OrgsLive.Index, :index
    live "/orgs/:org_slug", OrgsLive.Show, :show

    # Legacy routes (redirect to org-scoped)
    live "/projects", ProjectsLive.Index, :index
    live "/projects/:project_slug/nodes", NodesLive.Index, :index
    live "/projects/:project_slug/nodes/:id", NodesLive.Show, :show
    live "/projects/:project_slug/bundles", BundlesLive.Index, :index
    live "/projects/:project_slug/bundles/new", BundlesLive.New, :new
    live "/projects/:project_slug/bundles/diff", BundlesLive.Diff, :diff
    live "/projects/:project_slug/bundles/:id", BundlesLive.Show, :show
    live "/projects/:project_slug/rollouts", RolloutsLive.Index, :index
    live "/projects/:project_slug/rollouts/templates", RolloutTemplatesLive.Index, :index
    live "/projects/:project_slug/rollouts/:id", RolloutsLive.Show, :show
    live "/projects/:project_slug/drift", DriftLive.Index, :index
    live "/projects/:project_slug/drift/:id", DriftLive.Show, :show
    live "/projects/:project_slug/node-groups", NodeGroupsLive.Index, :index
    live "/projects/:project_slug/health-checks", HealthChecksLive.Index, :index
    live "/projects/:project_slug/environments", EnvironmentsLive.Index, :index
    live "/projects/:project_slug/validation-rules", ValidationRulesLive.Index, :index
    live "/projects/:project_slug/webhooks", WebhooksLive.Index, :index
    live "/projects/:project_slug/services", ServicesLive.Index, :index
    live "/projects/:project_slug/services/new", ServicesLive.New, :new
    live "/projects/:project_slug/services/:id", ServicesLive.Show, :show
    live "/projects/:project_slug/services/:id/edit", ServicesLive.Edit, :edit
    live "/projects/:project_slug/upstream-groups", UpstreamGroupsLive.Index, :index
    live "/projects/:project_slug/upstream-groups/new", UpstreamGroupsLive.New, :new
    live "/projects/:project_slug/upstream-groups/:id", UpstreamGroupsLive.Show, :show
    live "/projects/:project_slug/upstream-groups/:id/edit", UpstreamGroupsLive.Edit, :edit
    live "/projects/:project_slug/certificates", CertificatesLive.Index, :index
    live "/projects/:project_slug/certificates/new", CertificatesLive.New, :new
    live "/projects/:project_slug/certificates/:id", CertificatesLive.Show, :show
    live "/projects/:project_slug/certificates/:id/edit", CertificatesLive.Edit, :edit
    live "/projects/:project_slug/auth-policies", AuthPoliciesLive.Index, :index
    live "/projects/:project_slug/auth-policies/new", AuthPoliciesLive.New, :new
    live "/projects/:project_slug/auth-policies/:id", AuthPoliciesLive.Show, :show
    live "/projects/:project_slug/auth-policies/:id/edit", AuthPoliciesLive.Edit, :edit

    # Org-scoped dashboard
    live "/orgs/:org_slug/dashboard", DashboardLive.Index, :index

    # Org-scoped project routes
    live "/orgs/:org_slug/projects", ProjectsLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/nodes", NodesLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/nodes/:id", NodesLive.Show, :show
    live "/orgs/:org_slug/projects/:project_slug/bundles", BundlesLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/bundles/new", BundlesLive.New, :new
    live "/orgs/:org_slug/projects/:project_slug/bundles/diff", BundlesLive.Diff, :diff
    live "/orgs/:org_slug/projects/:project_slug/bundles/:id", BundlesLive.Show, :show
    live "/orgs/:org_slug/projects/:project_slug/rollouts", RolloutsLive.Index, :index

    live "/orgs/:org_slug/projects/:project_slug/rollouts/templates",
         RolloutTemplatesLive.Index,
         :index

    live "/orgs/:org_slug/projects/:project_slug/rollouts/:id", RolloutsLive.Show, :show
    live "/orgs/:org_slug/projects/:project_slug/drift", DriftLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/drift/:id", DriftLive.Show, :show
    live "/orgs/:org_slug/projects/:project_slug/node-groups", NodeGroupsLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/health-checks", HealthChecksLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/environments", EnvironmentsLive.Index, :index

    live "/orgs/:org_slug/projects/:project_slug/validation-rules",
         ValidationRulesLive.Index,
         :index

    live "/orgs/:org_slug/projects/:project_slug/webhooks", WebhooksLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/services", ServicesLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/services/new", ServicesLive.New, :new
    live "/orgs/:org_slug/projects/:project_slug/services/:id", ServicesLive.Show, :show
    live "/orgs/:org_slug/projects/:project_slug/services/:id/edit", ServicesLive.Edit, :edit
    live "/orgs/:org_slug/projects/:project_slug/upstream-groups", UpstreamGroupsLive.Index, :index
    live "/orgs/:org_slug/projects/:project_slug/upstream-groups/new", UpstreamGroupsLive.New, :new
    live "/orgs/:org_slug/projects/:project_slug/upstream-groups/:id", UpstreamGroupsLive.Show, :show

    live "/orgs/:org_slug/projects/:project_slug/upstream-groups/:id/edit",
         UpstreamGroupsLive.Edit,
         :edit

    live "/orgs/:org_slug/projects/:project_slug/certificates",
         CertificatesLive.Index,
         :index

    live "/orgs/:org_slug/projects/:project_slug/certificates/new",
         CertificatesLive.New,
         :new

    live "/orgs/:org_slug/projects/:project_slug/certificates/:id",
         CertificatesLive.Show,
         :show

    live "/orgs/:org_slug/projects/:project_slug/certificates/:id/edit",
         CertificatesLive.Edit,
         :edit

    live "/orgs/:org_slug/projects/:project_slug/auth-policies",
         AuthPoliciesLive.Index,
         :index

    live "/orgs/:org_slug/projects/:project_slug/auth-policies/new",
         AuthPoliciesLive.New,
         :new

    live "/orgs/:org_slug/projects/:project_slug/auth-policies/:id",
         AuthPoliciesLive.Show,
         :show

    live "/orgs/:org_slug/projects/:project_slug/auth-policies/:id/edit",
         AuthPoliciesLive.Edit,
         :edit
  end

  # Admin-only browser routes
  scope "/", SentinelCpWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/audit", AuditLive.Index, :index
    get "/audit/export", AuditController, :export
    live "/api-keys", ApiKeysLive.Index, :index
    live "/approvals", ApprovalsLive.Index, :index
    live "/schedule", ScheduleLive.Index, :index
    live "/profile", ProfileLive.Index, :index
  end

  # Webhook endpoints (verified by signature, not API key)
  scope "/api/v1/webhooks", SentinelCpWeb.Api do
    pipe_through :api

    post "/github", WebhookController, :github
  end

  # Node-facing API (called by Sentinel nodes)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through :api

    # Node registration (no auth required - returns node key)
    post "/projects/:project_slug/nodes/register", NodeController, :register
  end

  # Node-authenticated endpoints
  scope "/api/v1/nodes", SentinelCpWeb.Api do
    pipe_through [:api, :node_auth]

    post "/:node_id/heartbeat", NodeController, :heartbeat
    get "/:node_id/bundles/latest", NodeController, :latest_bundle
    post "/:node_id/token", NodeController, :token
    post "/:node_id/events", NodeController, :events
    post "/:node_id/config", NodeController, :config
  end

  # Control plane API — Nodes (read)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_nodes_read]

    scope "/projects/:project_slug" do
      get "/nodes", ProjectNodesController, :index
      get "/nodes/stats", ProjectNodesController, :stats
      get "/nodes/:id", ProjectNodesController, :show

      # Drift events (read)
      get "/drift", DriftController, :index
      get "/drift/stats", DriftController, :stats
      get "/drift/export", DriftController, :export
      get "/drift/:id", DriftController, :show
    end
  end

  # Control plane API — Nodes (write)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_nodes_write]

    scope "/projects/:project_slug" do
      delete "/nodes/:id", ProjectNodesController, :delete

      # Drift events (write)
      post "/drift/:id/resolve", DriftController, :resolve
      post "/drift/resolve-all", DriftController, :resolve_all
    end
  end

  # Control plane API — Bundles (read)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_bundles_read]

    scope "/projects/:project_slug" do
      get "/bundles", BundleController, :index
      get "/bundles/:id", BundleController, :show
      get "/bundles/:id/download", BundleController, :download
      get "/bundles/:id/verify", BundleController, :verify
      get "/bundles/:id/sbom", SbomController, :show
    end
  end

  # Control plane API — Bundles (write)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_bundles_write]

    scope "/projects/:project_slug" do
      post "/bundles", BundleController, :create
      post "/bundles/:id/assign", BundleController, :assign
      post "/bundles/:id/revoke", BundleController, :revoke
    end
  end

  # Control plane API — Rollouts (read)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_rollouts_read]

    scope "/projects/:project_slug" do
      get "/rollouts", RolloutController, :index
      get "/rollouts/:id", RolloutController, :show
    end
  end

  # Control plane API — Rollouts (write)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_rollouts_write]

    scope "/projects/:project_slug" do
      post "/rollouts", RolloutController, :create
      post "/rollouts/:id/pause", RolloutController, :pause
      post "/rollouts/:id/resume", RolloutController, :resume
      post "/rollouts/:id/cancel", RolloutController, :cancel
      post "/rollouts/:id/rollback", RolloutController, :rollback
    end
  end

  # Control plane API — Services (read)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_services_read]

    scope "/projects/:project_slug" do
      get "/services/preview-kdl", ServiceController, :preview_kdl
      get "/services", ServiceController, :index
      get "/services/:id", ServiceController, :show

      get "/upstream-groups", UpstreamGroupController, :index
      get "/upstream-groups/:id", UpstreamGroupController, :show

      get "/certificates", CertificateController, :index
      get "/certificates/:id", CertificateController, :show
      get "/certificates/:id/download", CertificateController, :download

      get "/auth-policies", AuthPolicyController, :index
      get "/auth-policies/:id", AuthPolicyController, :show
    end
  end

  # Control plane API — Services (write)
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_services_write]

    scope "/projects/:project_slug" do
      post "/services/generate-bundle", ServiceController, :generate_bundle
      put "/services/reorder", ServiceController, :reorder
      post "/services", ServiceController, :create
      put "/services/:id", ServiceController, :update
      delete "/services/:id", ServiceController, :delete

      post "/upstream-groups", UpstreamGroupController, :create
      put "/upstream-groups/:id", UpstreamGroupController, :update
      delete "/upstream-groups/:id", UpstreamGroupController, :delete
      post "/upstream-groups/:id/targets", UpstreamGroupController, :add_target
      put "/upstream-groups/:id/targets/:target_id", UpstreamGroupController, :update_target
      delete "/upstream-groups/:id/targets/:target_id", UpstreamGroupController, :delete_target

      post "/certificates", CertificateController, :create
      put "/certificates/:id", CertificateController, :update
      delete "/certificates/:id", CertificateController, :delete

      post "/auth-policies", AuthPolicyController, :create
      put "/auth-policies/:id", AuthPolicyController, :update
      delete "/auth-policies/:id", AuthPolicyController, :delete
    end
  end

  # Control plane API — API Key management
  scope "/api/v1", SentinelCpWeb.Api do
    pipe_through [:api, :api_auth, :require_api_keys_admin]

    post "/api-keys", ApiKeyController, :create
    get "/api-keys", ApiKeyController, :index
    get "/api-keys/:id", ApiKeyController, :show
    post "/api-keys/:id/revoke", ApiKeyController, :revoke
    delete "/api-keys/:id", ApiKeyController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sentinel_cp, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SentinelCpWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
