defmodule ZentinelCp.Observability.SliWorker do
  @moduledoc """
  Oban worker that periodically recomputes SLI values for all enabled SLOs.

  Runs every 5 minutes, fetches all enabled SLOs across all projects,
  and calls `SliComputer.compute/1` for each.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 300]

  require Logger

  alias ZentinelCp.Observability
  alias ZentinelCp.Observability.SliComputer

  @check_interval_seconds 300

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    slos = Observability.list_all_enabled_slos()

    results =
      Enum.map(slos, fn slo ->
        case SliComputer.compute(slo) do
          {:ok, updated} ->
            {:ok, updated}

          {:error, reason} ->
            Logger.warning("SliWorker: failed to compute SLO #{slo.id}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    ok_count = Enum.count(results, &match?({:ok, _}, &1))
    Logger.debug("SliWorker: computed #{ok_count}/#{length(slos)} SLOs")

    schedule_next()
    :ok
  end

  @doc """
  Ensures the SLI worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 120) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
