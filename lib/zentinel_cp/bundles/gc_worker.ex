defmodule ZentinelCp.Bundles.GcWorker do
  @moduledoc """
  Oban worker that removes old, unused bundles and their stored artifacts.
  Runs daily. `:bundle_retention_count` bundles are kept per project, default 50.
  See `ZentinelCp.Bundles.collect_garbage/1` for what counts as unused.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 43_200, states: [:available, :scheduled, :retryable]]

  require Logger

  alias ZentinelCp.Bundles

  @check_interval_seconds 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    keep = Application.get_env(:zentinel_cp, :bundle_retention_count, 50)
    count = Bundles.collect_garbage(keep)
    if count > 0, do: Logger.info("Bundle GC removed #{count} bundles")
    ensure_started()
    :ok
  end

  @doc "Ensures the worker is scheduled. Safe to call multiple times."
  def ensure_started do
    %{} |> new(schedule_in: @check_interval_seconds) |> Oban.insert()
  end
end
