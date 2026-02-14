defmodule SentinelCp.Events do
  @moduledoc """
  The Events context replaces the old Notifications module with a structured
  event bus, notification channels, and delivery rules.

  ## Usage

      SentinelCp.Events.emit("rollout.started", %{rollout_id: id}, project_id: project.id)

  Events are stored, matched against notification rules, and delivered
  to configured channels via Oban background workers.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Events.{Event, Channel, NotificationRule, DeliveryAttempt, DeliveryWorker}

  require Logger

  @events_topic "events"

  ## Event Emission

  @doc """
  Emits a structured event and triggers notification delivery.

  ## Options
    - `:project_id` - scopes the event to a project
    - `:org_id` - scopes the event to an org
  """
  def emit(type, payload \\ %{}, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      type: type,
      payload: payload,
      project_id: opts[:project_id],
      org_id: opts[:org_id],
      emitted_at: now
    }

    case create_event(attrs) do
      {:ok, event} ->
        Phoenix.PubSub.broadcast(SentinelCp.PubSub, @events_topic, {:event_emitted, event})
        schedule_deliveries(event)
        {:ok, event}

      {:error, reason} ->
        Logger.warning("Failed to emit event", type: type, error: inspect(reason))
        {:error, reason}
    end
  end

  ## Event CRUD

  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def get_event(id), do: Repo.get(Event, id)

  def list_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    project_id = Keyword.get(opts, :project_id)
    type_prefix = Keyword.get(opts, :type_prefix)

    query = from(e in Event, order_by: [desc: e.emitted_at], limit: ^limit)

    query =
      if project_id do
        where(query, [e], e.project_id == ^project_id)
      else
        query
      end

    query =
      if type_prefix do
        where(query, [e], like(e.type, ^"#{type_prefix}%"))
      else
        query
      end

    Repo.all(query)
  end

  ## Channel Management

  def list_channels(project_id) do
    from(c in Channel, where: c.project_id == ^project_id, order_by: [asc: c.name])
    |> Repo.all()
  end

  def get_channel(id), do: Repo.get(Channel, id)

  def get_channel!(id), do: Repo.get!(Channel, id)

  def create_channel(attrs) do
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update()
  end

  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  end

  ## Notification Rules

  def list_rules(project_id) do
    from(r in NotificationRule,
      where: r.project_id == ^project_id,
      order_by: [asc: r.name],
      preload: [:channel]
    )
    |> Repo.all()
  end

  def get_rule(id), do: Repo.get(NotificationRule, id)

  def create_rule(attrs) do
    %NotificationRule{}
    |> NotificationRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_rule(%NotificationRule{} = rule, attrs) do
    rule
    |> NotificationRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_rule(%NotificationRule{} = rule) do
    Repo.delete(rule)
  end

  ## Delivery

  @doc """
  Finds matching notification rules for an event and schedules deliveries.
  """
  def schedule_deliveries(%Event{} = event) do
    project_id = event.project_id

    if project_id do
      matching_rules =
        from(r in NotificationRule,
          where: r.project_id == ^project_id and r.enabled == true,
          preload: [:channel]
        )
        |> Repo.all()
        |> Enum.filter(fn rule ->
          Event.matches_pattern?(event.type, rule.event_pattern) and
            rule.channel.enabled
        end)

      Enum.each(matching_rules, fn rule ->
        schedule_delivery(event, rule.channel)
      end)

      {:ok, length(matching_rules)}
    else
      {:ok, 0}
    end
  end

  defp schedule_delivery(event, channel) do
    {:ok, attempt} =
      %DeliveryAttempt{}
      |> DeliveryAttempt.changeset(%{
        event_id: event.id,
        channel_id: channel.id,
        status: "pending",
        attempt_number: 1
      })
      |> Repo.insert()

    DeliveryWorker.enqueue(attempt.id)
  end

  ## Delivery Attempts

  def get_delivery_attempt(id), do: Repo.get(DeliveryAttempt, id)

  def get_delivery_attempt!(id), do: Repo.get!(DeliveryAttempt, id)

  @doc """
  Sends a test notification through a channel by creating a synthetic
  `system.test` event and scheduling delivery.
  """
  def test_channel(%Channel{} = channel) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, event} =
      create_event(%{
        type: "system.test",
        payload: %{
          channel_id: channel.id,
          channel_name: channel.name,
          message: "Test notification from Sentinel CP"
        },
        project_id: channel.project_id,
        emitted_at: now
      })

    {:ok, attempt} =
      %DeliveryAttempt{}
      |> DeliveryAttempt.changeset(%{
        event_id: event.id,
        channel_id: channel.id,
        status: "pending",
        attempt_number: 1
      })
      |> Repo.insert()

    DeliveryWorker.enqueue(attempt.id)
    {:ok, attempt}
  end

  @doc """
  Lists all delivery attempts for a given event+channel pair, ordered by attempt number.
  Used to show the retry timeline for a delivery.
  """
  def list_attempt_chain(event_id, channel_id) do
    from(d in DeliveryAttempt,
      where: d.event_id == ^event_id and d.channel_id == ^channel_id,
      order_by: [asc: d.attempt_number],
      preload: [:event, :channel]
    )
    |> Repo.all()
  end

  def list_delivery_attempts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    channel_id = Keyword.get(opts, :channel_id)
    status = Keyword.get(opts, :status)
    project_id = Keyword.get(opts, :project_id)

    query =
      from(d in DeliveryAttempt,
        order_by: [desc: d.inserted_at],
        limit: ^limit,
        preload: [:event, :channel]
      )

    query =
      if project_id do
        from(d in query,
          join: c in Channel,
          on: d.channel_id == c.id,
          where: c.project_id == ^project_id
        )
      else
        query
      end

    query =
      if channel_id do
        where(query, [d], d.channel_id == ^channel_id)
      else
        query
      end

    query =
      if status do
        where(query, [d], d.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Manually retries a failed delivery from the dead-letter queue.
  """
  def retry_delivery(attempt_id) do
    attempt = Repo.get!(DeliveryAttempt, attempt_id)

    if attempt.status == "dead_letter" do
      {:ok, new_attempt} =
        %DeliveryAttempt{}
        |> DeliveryAttempt.changeset(%{
          event_id: attempt.event_id,
          channel_id: attempt.channel_id,
          status: "pending",
          attempt_number: 1
        })
        |> Repo.insert()

      DeliveryWorker.enqueue(new_attempt.id)
      {:ok, new_attempt}
    else
      {:error, :not_in_dead_letter}
    end
  end

  ## Delivery Stats

  def delivery_stats(project_id, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    since = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    query =
      from(d in DeliveryAttempt,
        join: c in Channel,
        on: d.channel_id == c.id,
        where: c.project_id == ^project_id and d.inserted_at >= ^since,
        group_by: d.status,
        select: {d.status, count(d.id)}
      )

    stats = Repo.all(query) |> Map.new()

    %{
      total: Enum.sum(Map.values(stats)),
      delivered: Map.get(stats, "delivered", 0),
      failed: Map.get(stats, "failed", 0),
      dead_letter: Map.get(stats, "dead_letter", 0),
      pending: Map.get(stats, "pending", 0)
    }
  end

  ## PubSub

  def subscribe do
    Phoenix.PubSub.subscribe(SentinelCp.PubSub, @events_topic)
  end

  ## Legacy Compatibility
  ## These functions maintain backward compatibility with existing notification call sites

  def notify_rollout_state_change(rollout, old_state, new_state) do
    event_type =
      case new_state do
        "running" -> "rollout.started"
        "completed" -> "rollout.completed"
        "failed" -> "rollout.failed"
        "cancelled" -> "rollout.cancelled"
        "paused" -> "rollout.paused"
        _ -> "rollout.state_changed"
      end

    emit(
      event_type,
      %{
        rollout_id: rollout.id,
        bundle_id: rollout.bundle_id,
        strategy: rollout.strategy,
        old_state: old_state,
        new_state: new_state
      },
      project_id: rollout.project_id
    )
  end

  def notify_rollout_approved(rollout, approver) do
    emit(
      "rollout.approved",
      %{
        rollout_id: rollout.id,
        approver_id: approver.id,
        approver_email: approver.email
      },
      project_id: rollout.project_id
    )
  end

  def notify_rollout_rejected(rollout, rejecter, comment) do
    emit(
      "rollout.rejected",
      %{
        rollout_id: rollout.id,
        rejected_by_id: rejecter.id,
        rejected_by_email: rejecter.email,
        comment: comment
      },
      project_id: rollout.project_id
    )
  end

  def notify_drift_detected(node, event, project) do
    emit(
      "drift.detected",
      %{
        node_id: node.id,
        node_name: node.name,
        expected_bundle_id: event.expected_bundle_id,
        actual_bundle_id: event.actual_bundle_id
      },
      project_id: project.id
    )
  end

  def notify_drift_resolved(node, event, project) do
    emit(
      "drift.resolved",
      %{
        node_id: node.id,
        node_name: node.name,
        resolution: event.resolution
      },
      project_id: project.id
    )
  end

  def notify_drift_threshold_exceeded(project, drift_stats) do
    emit(
      "drift.threshold_exceeded",
      %{
        total_managed: drift_stats.total_managed,
        drifted: drift_stats.drifted
      },
      project_id: project.id
    )
  end
end
