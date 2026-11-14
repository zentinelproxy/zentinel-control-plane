defmodule ZentinelCp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry auto-instrumentation
    # Bandit opens the HTTP server span; Phoenix adds the route to it.
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
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
      {Task.Supervisor, name: ZentinelCp.TaskSupervisor},
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
        start_periodic_workers()

      _ ->
        :ok
    end

    result
  end

  # Each worker reschedules itself, and uniqueness stops several instances from
  # running duplicates of the same job. Uniqueness must not include `:executing`:
  # a running job would then count as a duplicate of its own next run, which would
  # be dropped, ending the schedule.
  @periodic_workers [
    ZentinelCp.Rollouts.SchedulerWorker,
    ZentinelCp.Rollouts.PromotionWorker,
    ZentinelCp.Nodes.DriftWorker,
    ZentinelCp.Nodes.StalenessWorker,
    ZentinelCp.Nodes.HeartbeatPruneWorker,
    ZentinelCp.Bundles.GcWorker,
    ZentinelCp.Services.CertificateExpiryWorker,
    ZentinelCp.Services.IssuedCertificateExpiryWorker,
    ZentinelCp.Services.CertificateRenewalWorker,
    ZentinelCp.Services.DiscoverySyncWorker,
    ZentinelCp.Analytics.PruneWorker,
    ZentinelCp.Analytics.RollupWorker,
    ZentinelCp.Analytics.WafEventPruneWorker,
    ZentinelCp.Analytics.WafBaselineWorker,
    ZentinelCp.Analytics.WafAnomalyWorker,
    ZentinelCp.Observability.SliWorker,
    ZentinelCp.Observability.AlertEvaluator,
    ZentinelCp.Federation.SyncWorker
  ]

  @doc false
  def periodic_workers, do: @periodic_workers

  defp start_periodic_workers do
    unless Application.get_env(:zentinel_cp, Oban, [])[:testing] do
      Enum.each(@periodic_workers, & &1.ensure_started())
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ZentinelCpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
