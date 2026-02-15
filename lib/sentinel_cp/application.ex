defmodule SentinelCp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry auto-instrumentation
    OpentelemetryPhoenix.setup()
    OpentelemetryEcto.setup([:sentinel_cp, :repo])

    children = [
      SentinelCpWeb.Telemetry,
      SentinelCp.Repo,
      {DNSCluster, query: Application.get_env(:sentinel_cp, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SentinelCp.PubSub},
      # Prometheus metrics (must start before Endpoint)
      SentinelCp.PromEx,
      # API rate limiting (ETS-backed token bucket)
      SentinelCp.RateLimit,
      # ACME challenge token store (ETS-backed)
      SentinelCp.Services.Acme.ChallengeStore,
      # Background job processing
      {Oban, Application.fetch_env!(:sentinel_cp, Oban)},
      # Start to serve requests, typically the last entry
      SentinelCpWeb.Endpoint,
      # GraphQL subscriptions (must start after Endpoint)
      {Absinthe.Subscription, SentinelCpWeb.Endpoint}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SentinelCp.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Start periodic workers (only if supervisor started successfully)
    case result do
      {:ok, _pid} ->
        SentinelCp.Rollouts.SchedulerWorker.ensure_started()
        SentinelCp.Nodes.DriftWorker.ensure_started()
        SentinelCp.Services.CertificateExpiryWorker.ensure_started()
        SentinelCp.Analytics.PruneWorker.ensure_started()
        SentinelCp.Services.DiscoverySyncWorker.ensure_started()
        SentinelCp.Services.CertificateRenewalWorker.ensure_started()
        SentinelCp.Analytics.WafEventPruneWorker.ensure_started()
        SentinelCp.Analytics.WafBaselineWorker.ensure_started()
        SentinelCp.Analytics.WafAnomalyWorker.ensure_started()

      _ ->
        :ok
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SentinelCpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
