defmodule ZentinelCp.Analytics.WafEventPruneWorker do
  @moduledoc """
  Oban worker that prunes old WAF events.

  Runs daily and deletes waf_events older than the retention period (default 30 days).
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 86_400]

  require Logger

  alias ZentinelCp.Analytics

  @check_interval_seconds 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_days = Application.get_env(:zentinel_cp, :waf_retention_days, 30)

    case Analytics.prune_old_waf_events(retention_days) do
      {:ok, 0} ->
        Logger.debug("WafEventPruneWorker: no old WAF events to prune")

      {:ok, count} ->
        Logger.info("WafEventPruneWorker: pruned #{count} old WAF events")
    end

    schedule_next()
    :ok
  end

  @doc """
  Ensures the WAF prune worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 300) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
