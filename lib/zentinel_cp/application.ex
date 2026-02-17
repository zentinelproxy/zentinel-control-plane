defmodule ZentinelCp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry auto-instrumentation
    OpentelemetryPhoenix.setup()
    OpentelemetryEcto.setup([:zentinel_cp, :repo])

    children = [
      ZentinelCpWeb.Telemetry,
      ZentinelCp.Repo,
      {DNSCluster, query: Application.get_env(:zentinel_cp, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ZentinelCp.PubSub},
      # Prometheus metrics (must start before Endpoint)
      ZentinelCp.PromEx,
      # API rate limiting (ETS-backed token bucket)
      ZentinelCp.RateLimit,
      # ACME challenge token store (ETS-backed)
      ZentinelCp.Services.Acme.ChallengeStore,
      # Background job processing
      {Oban, Application.fetch_env!(:zentinel_cp, Oban)},
      # Start to serve requests, typically the last entry
      ZentinelCpWeb.Endpoint,
      # GraphQL subscriptions (must start after Endpoint)
      {Absinthe.Subscription, ZentinelCpWeb.Endpoint}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZentinelCp.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Start periodic workers (only if supervisor started successfully)
    case result do
      {:ok, _pid} ->
        ZentinelCp.Rollouts.SchedulerWorker.ensure_started()
        ZentinelCp.Nodes.DriftWorker.ensure_started()
        ZentinelCp.Services.CertificateExpiryWorker.ensure_started()
        ZentinelCp.Analytics.PruneWorker.ensure_started()
        ZentinelCp.Services.DiscoverySyncWorker.ensure_started()
        ZentinelCp.Services.CertificateRenewalWorker.ensure_started()
        ZentinelCp.Analytics.WafEventPruneWorker.ensure_started()
        ZentinelCp.Analytics.WafBaselineWorker.ensure_started()
        ZentinelCp.Analytics.WafAnomalyWorker.ensure_started()

      _ ->
        :ok
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ZentinelCpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
