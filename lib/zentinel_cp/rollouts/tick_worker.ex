defmodule ZentinelCp.Rollouts.TickWorker do
  @moduledoc """
  Oban worker that drives rollout progression.

  Self-scheduling: each tick reschedules itself in 5 seconds if the rollout
  is still running. Uses unique constraint to prevent duplicate ticks.
  """
  use Oban.Worker,
    queue: :rollouts,
    max_attempts: 3,
    unique: [keys: [:rollout_id], period: 10]

  require Logger

  alias ZentinelCp.Observability.Tracer
  alias ZentinelCp.Rollouts

  @tick_interval_seconds 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rollout_id" => rollout_id}}) do
    case Rollouts.get_rollout(rollout_id) do
      nil ->
        Logger.warning("TickWorker: rollout #{rollout_id} not found, stopping")
        :ok

      %{state: "running"} = rollout ->
        Logger.debug("TickWorker: ticking rollout #{rollout_id}")
        result = Tracer.trace_rollout_tick(rollout_id, fn -> Rollouts.tick_rollout(rollout) end)
        handle_tick_result(result, rollout_id)

      %{state: state} ->
        Logger.info("TickWorker: rollout #{rollout_id} in state #{state}, stopping ticks")
        :ok
    end
  end

  defp handle_tick_result({:ok, result}, rollout_id)
       when result in ~w(step_started step_verifying step_completed waiting)a do
    reschedule(rollout_id)
    :ok
  end

  defp handle_tick_result({:ok, %Rollouts.Rollout{state: "completed"}}, rollout_id) do
    Logger.info("TickWorker: rollout #{rollout_id} completed")
    :ok
  end

  defp handle_tick_result({:ok, :deadline_exceeded}, rollout_id) do
    Logger.warning("TickWorker: rollout #{rollout_id} failed (deadline exceeded)")
    :ok
  end

  defp handle_tick_result({:ok, :not_running}, rollout_id) do
    Logger.info("TickWorker: rollout #{rollout_id} is no longer running")
    :ok
  end

  defp reschedule(rollout_id) do
    # Skip rescheduling in Oban inline/testing mode to prevent infinite recursion
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{rollout_id: rollout_id}
      |> __MODULE__.new(schedule_in: @tick_interval_seconds)
      |> Oban.insert()
    end
  end
end
