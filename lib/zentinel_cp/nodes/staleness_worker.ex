defmodule ZentinelCp.Nodes.StalenessWorker do
  @moduledoc """
  Oban worker that marks nodes offline when their heartbeats stop.
  Runs every minute.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30, states: [:available, :scheduled, :retryable]]

  alias ZentinelCp.Nodes

  @check_interval_seconds 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Nodes.mark_stale_nodes_offline()
    ensure_started()
    :ok
  end

  @doc "Ensures the worker is scheduled. Safe to call multiple times."
  def ensure_started do
    %{} |> new(schedule_in: @check_interval_seconds) |> Oban.insert()
  end
end
