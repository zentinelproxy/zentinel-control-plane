defmodule ZentinelCp.NotificationFixtures do
  @moduledoc """
  Test helpers for creating notification channels, rules, events, and delivery attempts.
  """

  alias ZentinelCp.Events
  alias ZentinelCp.Events.DeliveryAttempt
  alias ZentinelCp.ProjectsFixtures
  alias ZentinelCp.Repo

  def unique_channel_name, do: "channel-#{System.unique_integer([:positive])}"
  def unique_rule_name, do: "rule-#{System.unique_integer([:positive])}"

  def channel_fixture(attrs \\ %{}) do
    project = attrs[:project] || ProjectsFixtures.project_fixture()

    {:ok, channel} =
      Events.create_channel(%{
        project_id: project.id,
        name: attrs[:name] || unique_channel_name(),
        type: attrs[:type] || "slack",
        config: attrs[:config] || %{"webhook_url" => "https://hooks.slack.com/test"},
        enabled: Map.get(attrs, :enabled, true)
      })

    channel
  end

  def rule_fixture(attrs \\ %{}) do
    project = attrs[:project] || ProjectsFixtures.project_fixture()
    channel = attrs[:channel] || channel_fixture(%{project: project})

    {:ok, rule} =
      Events.create_rule(%{
        project_id: project.id,
        name: attrs[:name] || unique_rule_name(),
        event_pattern: attrs[:event_pattern] || "rollout.*",
        channel_id: channel.id,
        enabled: Map.get(attrs, :enabled, true)
      })

    rule
  end

  def event_fixture(attrs \\ %{}) do
    project = attrs[:project] || ProjectsFixtures.project_fixture()

    {:ok, event} =
      Events.create_event(%{
        type: attrs[:type] || "rollout.started",
        payload: attrs[:payload] || %{},
        project_id: project.id,
        emitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    event
  end

  def delivery_attempt_fixture(attrs \\ %{}) do
    project = attrs[:project] || ProjectsFixtures.project_fixture()
    channel = attrs[:channel] || channel_fixture(%{project: project})
    event = attrs[:event] || event_fixture(%{project: project})

    {:ok, attempt} =
      Repo.insert(
        DeliveryAttempt.changeset(
          %DeliveryAttempt{},
          %{
            event_id: event.id,
            channel_id: channel.id,
            status: attrs[:status] || "delivered",
            attempt_number: attrs[:attempt_number] || 1,
            http_status: attrs[:http_status] || 200,
            latency_ms: attrs[:latency_ms] || 150,
            error: attrs[:error],
            request_body: attrs[:request_body] || ~s({"test": true}),
            response_body: attrs[:response_body] || ~s({"ok": true})
          }
        )
      )

    attempt
  end
end
