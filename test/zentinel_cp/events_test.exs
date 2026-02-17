defmodule ZentinelCp.EventsTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Events
  alias ZentinelCp.Events.Event
  import ZentinelCp.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  describe "emit/3" do
    test "creates an event with valid type", %{project: project} do
      assert {:ok, event} =
               Events.emit("rollout.started", %{rollout_id: "abc"}, project_id: project.id)

      assert event.type == "rollout.started"
      assert event.payload == %{rollout_id: "abc"}
      assert event.project_id == project.id
      assert event.emitted_at != nil
    end

    test "rejects invalid event type prefix" do
      assert {:error, changeset} = Events.emit("invalid.event")
      assert "must start with one of:" <> _ = hd(errors_on(changeset).type)
    end

    test "supports all event type prefixes" do
      for prefix <- ~w(rollout bundle node drift secret security system) do
        assert {:ok, _} = Events.emit("#{prefix}.test")
      end
    end
  end

  describe "channel management" do
    test "creates a Slack channel", %{project: project} do
      assert {:ok, channel} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "alerts-slack",
                 type: "slack",
                 config: %{"webhook_url" => "https://hooks.slack.com/test"}
               })

      assert channel.type == "slack"
      assert channel.signing_secret != nil
    end

    test "creates a PagerDuty channel", %{project: project} do
      assert {:ok, channel} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "pagerduty-prod",
                 type: "pagerduty",
                 config: %{"routing_key" => "abc123"}
               })

      assert channel.type == "pagerduty"
    end

    test "creates an email channel", %{project: project} do
      assert {:ok, channel} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "email-ops",
                 type: "email",
                 config: %{"to" => "ops@example.com"}
               })

      assert channel.type == "email"
    end

    test "creates a Teams channel", %{project: project} do
      assert {:ok, _} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "teams-channel",
                 type: "teams",
                 config: %{"webhook_url" => "https://teams.webhook.example.com"}
               })
    end

    test "creates a generic webhook channel", %{project: project} do
      assert {:ok, _} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "custom-webhook",
                 type: "webhook",
                 config: %{"url" => "https://my-service.example.com/webhook"}
               })
    end

    test "validates channel config", %{project: project} do
      assert {:error, changeset} =
               Events.create_channel(%{
                 project_id: project.id,
                 name: "bad-slack",
                 type: "slack",
                 config: %{"wrong_key" => "value"}
               })

      assert "slack channel requires webhook_url" in errors_on(changeset).config
    end

    test "enforces unique channel names per project", %{project: project} do
      attrs = %{
        project_id: project.id,
        name: "same-name",
        type: "webhook",
        config: %{"url" => "https://example.com"}
      }

      assert {:ok, _} = Events.create_channel(attrs)
      assert {:error, changeset} = Events.create_channel(attrs)
      assert "has already been taken" in errors_on(changeset).project_id
    end

    test "lists channels for a project", %{project: project} do
      {:ok, _} =
        Events.create_channel(%{
          project_id: project.id,
          name: "ch1",
          type: "webhook",
          config: %{"url" => "https://example.com/1"}
        })

      {:ok, _} =
        Events.create_channel(%{
          project_id: project.id,
          name: "ch2",
          type: "webhook",
          config: %{"url" => "https://example.com/2"}
        })

      channels = Events.list_channels(project.id)
      assert length(channels) == 2
    end
  end

  describe "notification rules" do
    setup %{project: project} do
      {:ok, channel} =
        Events.create_channel(%{
          project_id: project.id,
          name: "test-channel",
          type: "webhook",
          config: %{"url" => "https://example.com"}
        })

      %{channel: channel}
    end

    test "creates a notification rule", %{project: project, channel: channel} do
      assert {:ok, rule} =
               Events.create_rule(%{
                 project_id: project.id,
                 name: "notify on rollouts",
                 event_pattern: "rollout.*",
                 channel_id: channel.id
               })

      assert rule.event_pattern == "rollout.*"
    end

    test "validates event pattern", %{project: project, channel: channel} do
      assert {:error, changeset} =
               Events.create_rule(%{
                 project_id: project.id,
                 name: "bad pattern",
                 event_pattern: "INVALID!!!",
                 channel_id: channel.id
               })

      assert errors_on(changeset).event_pattern != nil
    end

    test "lists rules for a project", %{project: project, channel: channel} do
      {:ok, _} =
        Events.create_rule(%{
          project_id: project.id,
          name: "rule1",
          event_pattern: "rollout.*",
          channel_id: channel.id
        })

      rules = Events.list_rules(project.id)
      assert length(rules) == 1
    end
  end

  describe "event pattern matching" do
    test "matches exact event types" do
      assert Event.matches_pattern?("rollout.started", "rollout.started")
      refute Event.matches_pattern?("rollout.started", "rollout.completed")
    end

    test "matches wildcard patterns" do
      assert Event.matches_pattern?("rollout.started", "rollout.*")
      assert Event.matches_pattern?("rollout.completed", "rollout.*")
      refute Event.matches_pattern?("bundle.created", "rollout.*")
    end

    test "matches global wildcard" do
      assert Event.matches_pattern?("rollout.started", "*")
      assert Event.matches_pattern?("bundle.created", "*")
    end
  end

  describe "delivery scheduling" do
    setup %{project: project} do
      {:ok, channel} =
        Events.create_channel(%{
          project_id: project.id,
          name: "delivery-test",
          type: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        })

      {:ok, _rule} =
        Events.create_rule(%{
          project_id: project.id,
          name: "all rollouts",
          event_pattern: "rollout.*",
          channel_id: channel.id
        })

      %{channel: channel}
    end

    test "schedules deliveries for matching events", %{project: project} do
      {:ok, event} =
        Events.emit("rollout.started", %{id: "r1"}, project_id: project.id)

      # Should have created a delivery attempt (may already be processed by Oban)
      attempts = Events.list_delivery_attempts()
      assert Enum.any?(attempts, &(&1.event_id == event.id))
    end

    test "does not schedule deliveries for non-matching events", %{project: project} do
      before_count = length(Events.list_delivery_attempts())

      {:ok, _event} =
        Events.emit("bundle.created", %{id: "b1"}, project_id: project.id)

      after_count = length(Events.list_delivery_attempts())
      assert after_count == before_count
    end
  end

  describe "legacy compatibility" do
    test "notify_rollout_state_change emits event", %{project: project} do
      rollout = %{id: "r1", bundle_id: "b1", strategy: "rolling", project_id: project.id}

      assert {:ok, event} = Events.notify_rollout_state_change(rollout, "pending", "running")
      assert event.type == "rollout.started"
    end

    test "notify_drift_detected emits event", %{project: project} do
      node = %{id: "n1", name: "node-1"}
      drift_event = %{expected_bundle_id: "b1", actual_bundle_id: "b2"}

      assert {:ok, event} = Events.notify_drift_detected(node, drift_event, project)
      assert event.type == "drift.detected"
    end
  end

  describe "delivery stats" do
    test "returns stats for a project", %{project: project} do
      stats = Events.delivery_stats(project.id)
      assert stats.total >= 0
      assert Map.has_key?(stats, :delivered)
      assert Map.has_key?(stats, :failed)
      assert Map.has_key?(stats, :dead_letter)
    end
  end
end
