defmodule SentinelCp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SentinelCpWeb.Telemetry,
      SentinelCp.Repo,
      {DNSCluster, query: Application.get_env(:sentinel_cp, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SentinelCp.PubSub},
      # Prometheus metrics (must start before Endpoint)
      SentinelCp.PromEx,
      # Background job processing
      {Oban, Application.fetch_env!(:sentinel_cp, Oban)},
      # Start to serve requests, typically the last entry
      SentinelCpWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SentinelCp.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Start periodic workers
    SentinelCp.Rollouts.SchedulerWorker.ensure_started()
    SentinelCp.Nodes.DriftWorker.ensure_started()
    SentinelCp.Services.CertificateExpiryWorker.ensure_started()
    SentinelCp.Analytics.PruneWorker.ensure_started()
    SentinelCp.Services.DiscoverySyncWorker.ensure_started()

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
