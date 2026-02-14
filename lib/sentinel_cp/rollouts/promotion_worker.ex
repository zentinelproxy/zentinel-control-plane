defmodule SentinelCp.Rollouts.PromotionWorker do
  @moduledoc """
  Oban worker that evaluates promotion rules periodically
  and auto-promotes bundles across environments.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 60]

  import Ecto.Query
  alias SentinelCp.Repo
  alias SentinelCp.Projects.PromotionRule
  alias SentinelCp.Rollouts
  alias SentinelCp.Rollouts.Rollout

  require Logger

  @check_interval_seconds 60

  def ensure_started do
    %{}
    |> __MODULE__.new(schedule_in: @check_interval_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    rules =
      from(r in PromotionRule,
        where: r.enabled == true and r.auto_promote == true,
        preload: [:source_env, :target_env]
      )
      |> Repo.all()

    Enum.each(rules, &evaluate_rule/1)

    # Reschedule
    ensure_started()
    :ok
  end

  defp evaluate_rule(rule) do
    # Find completed rollouts in the source environment
    completed_rollouts =
      from(r in Rollout,
        where:
          r.project_id == ^rule.project_id and
            r.environment_id == ^rule.source_env_id and
            r.state == "completed",
        order_by: [desc: r.completed_at],
        limit: 1
      )
      |> Repo.all()

    Enum.each(completed_rollouts, fn rollout ->
      if should_promote?(rule, rollout) do
        promote_bundle(rule, rollout)
      end
    end)
  end

  defp should_promote?(rule, rollout) do
    # Check delay
    if rule.delay_minutes > 0 do
      delay_elapsed =
        DateTime.diff(DateTime.utc_now(), rollout.completed_at, :second) >=
          rule.delay_minutes * 60

      delay_elapsed
    else
      true
    end
  end

  defp promote_bundle(rule, rollout) do
    # Check if bundle already promoted to target
    existing =
      from(r in Rollout,
        where:
          r.project_id == ^rule.project_id and
            r.environment_id == ^rule.target_env_id and
            r.bundle_id == ^rollout.bundle_id
      )
      |> Repo.exists?()

    unless existing do
      Logger.info(
        "Auto-promoting bundle #{rollout.bundle_id} from #{rule.source_env_id} to #{rule.target_env_id}"
      )

      Rollouts.create_rollout(%{
        project_id: rule.project_id,
        bundle_id: rollout.bundle_id,
        environment_id: rule.target_env_id,
        target_selector: %{"type" => "all"},
        strategy: "rolling"
      })
    end
  end
end
