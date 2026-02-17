defmodule ZentinelCp.Analytics.PruneWorker do
  @moduledoc """
  Oban worker that prunes old request logs.

  Runs hourly and deletes request_logs older than the retention period (default 24h).
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  alias ZentinelCp.Analytics

  @check_interval_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_hours = Application.get_env(:zentinel_cp, :analytics_retention_hours, 24)

    case Analytics.prune_old_logs(retention_hours) do
      {:ok, 0} ->
        Logger.debug("PruneWorker: no old request logs to prune")

      {:ok, count} ->
        Logger.info("PruneWorker: pruned #{count} old request logs")
    end

    schedule_next()
    :ok
  end

  @doc """
  Ensures the prune worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 60) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
