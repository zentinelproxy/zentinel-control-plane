defmodule ZentinelCp.Rollouts.SchedulerWorker do
  @moduledoc """
  Oban worker that starts scheduled rollouts when their time arrives.

  Runs periodically and checks for pending rollouts with a scheduled_at time
  that has passed. Only starts rollouts that have the required approvals.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30]

  require Logger

  import Ecto.Query
  alias ZentinelCp.{Repo, Rollouts}
  alias ZentinelCp.Rollouts.Rollout

  @check_interval_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    due_rollouts = get_due_rollouts(now)

    Logger.debug("SchedulerWorker: checking #{length(due_rollouts)} due rollouts")

    for rollout <- due_rollouts do
      if Rollouts.can_start_rollout?(rollout) do
        case Rollouts.plan_rollout(rollout) do
          {:ok, started} ->
            Logger.info("SchedulerWorker: started scheduled rollout #{started.id}")

          {:error, reason} ->
            Logger.warning(
              "SchedulerWorker: failed to start rollout #{rollout.id}: #{inspect(reason)}"
            )
        end
      else
        Logger.debug("SchedulerWorker: rollout #{rollout.id} scheduled but awaiting approval")
      end
    end

    reschedule()
    :ok
  end

  defp get_due_rollouts(now) do
    Rollout
    |> where([r], r.state == "pending")
    |> where([r], not is_nil(r.scheduled_at))
    |> where([r], r.scheduled_at <= ^now)
    |> Repo.all()
  end

  defp reschedule do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new(schedule_in: @check_interval_seconds)
      |> Oban.insert()
    end
  end

  @doc """
  Starts the scheduler worker if not already running.
  Called during application startup.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new()
      |> Oban.insert()
    end
  end
end
