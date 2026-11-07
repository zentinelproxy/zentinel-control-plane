defmodule ZentinelCp.Nodes.HeartbeatPruneWorker do
  @moduledoc """
  Oban worker that deletes old node heartbeats, which otherwise grow without
  limit. Runs hourly. Retention is `:heartbeat_retention_days`, default 7.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 1800, states: [:available, :scheduled, :retryable]]

  alias ZentinelCp.Nodes

  @check_interval_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Nodes.prune_heartbeats(Application.get_env(:zentinel_cp, :heartbeat_retention_days, 7))
    ensure_started()
    :ok
  end

  @doc "Ensures the worker is scheduled. Safe to call multiple times."
  def ensure_started do
    %{} |> new(schedule_in: @check_interval_seconds) |> Oban.insert()
  end
end
