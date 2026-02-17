defmodule ZentinelCp.ObservabilityTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Observability
  alias ZentinelCp.Observability.{Slo, SliComputer, AlertRule, AlertState, AlertEvaluator, Tracer}
  alias ZentinelCp.Analytics.{ServiceMetric, MetricRollup, RollupWorker}

  import ZentinelCp.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  # ─── 15.1 Tracer ─────────────────────────────────────────────────

  describe "tracer" do
    test "span executes function and returns result" do
      result = Tracer.trace_compilation("bundle-123", fn -> {:ok, :compiled} end)
      assert result == {:ok, :compiled}
    end

    test "span re-raises exceptions" do
      assert_raise RuntimeError, "boom", fn ->
        Tracer.trace_compilation("bundle-456", fn -> raise "boom" end)
      end
    end

    test "trace_rollout_tick wraps function" do
      assert Tracer.trace_rollout_tick("rollout-1", fn -> :ticked end) == :ticked
    end

    test "trace_webhook wraps function" do
      assert Tracer.trace_webhook("github", fn -> :processed end) == :processed
    end

    test "trace_heartbeat wraps function" do
      assert Tracer.trace_heartbeat("node-1", fn -> :ok end) == :ok
    end
  end

  # ─── 15.2 SLO/SLI ───────────────────────────────────────────────

  describe "SLO schema" do
    test "creates a valid SLO", %{project: project} do
      changeset =
        Slo.changeset(%Slo{}, %{
          project_id: project.id,
          name: "API Availability",
          sli_type: "availability",
          target: 99.9,
          window_days: 30
        })

      assert changeset.valid?
    end

    test "validates SLI type" do
      changeset =
        Slo.changeset(%Slo{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad SLO",
          sli_type: "invalid_type",
          target: 99.0
        })

      assert "is invalid" in errors_on(changeset).sli_type
    end

    test "validates availability target range" do
      changeset =
        Slo.changeset(%Slo{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Target",
          sli_type: "availability",
          target: 150.0
        })

      assert "must be between 0 and 100 for availability" in errors_on(changeset).target
    end

    test "validates unique name per project", %{project: project} do
      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Unique SLO",
          sli_type: "availability",
          target: 99.9
        })

      {:error, changeset} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Unique SLO",
          sli_type: "error_rate",
          target: 1.0
        })

      errors = errors_on(changeset)
      # SQLite may report the unique constraint on either field in the composite index
      has_name_error = Map.has_key?(errors, :name) and "has already been taken" in errors.name

      has_project_error =
        Map.has_key?(errors, :project_id) and "has already been taken" in errors.project_id

      assert has_name_error or has_project_error
    end

    test "lists SLI types" do
      types = Slo.sli_types()
      assert "availability" in types
      assert "latency_p99" in types
      assert "error_rate" in types
    end
  end

  describe "SLI computation" do
    test "computes availability SLI with no data", %{project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Avail SLO",
          sli_type: "availability",
          target: 99.9
        })

      sli_value = SliComputer.current_sli(slo)
      # No data = 100% availability
      assert sli_value == 100.0
    end

    test "computes error_rate SLI with no data", %{project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Error Rate SLO",
          sli_type: "error_rate",
          target: 1.0
        })

      sli_value = SliComputer.current_sli(slo)
      assert sli_value == 0.0
    end

    test "compute updates SLO record", %{project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Computed SLO",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, updated} = SliComputer.compute(slo)
      assert updated.last_computed_at != nil
      assert updated.error_budget_remaining != nil
      assert updated.burn_rate != nil
    end

    test "compute_all_slis processes all enabled SLOs", %{project: project} do
      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "SLO A",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "SLO B",
          sli_type: "error_rate",
          target: 1.0
        })

      results = Observability.compute_all_slis(project.id)
      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "SLO CRUD" do
    test "creates, lists, and deletes SLOs", %{project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "CRUD SLO",
          sli_type: "availability",
          target: 99.9
        })

      assert [fetched] = Observability.list_slos(project.id)
      assert fetched.id == slo.id

      {:ok, _} = Observability.delete_slo(slo)
      assert [] == Observability.list_slos(project.id)
    end

    test "updates an SLO", %{project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Update SLO",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, updated} = Observability.update_slo(slo, %{target: 99.5})
      assert updated.target == 99.5
    end
  end

  # ─── 15.3 Alerting ──────────────────────────────────────────────

  describe "alert rule schema" do
    test "creates a valid metric alert rule", %{project: project} do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "High Error Rate",
          rule_type: "metric",
          condition: %{
            "metric" => "error_rate",
            "operator" => ">",
            "value" => 5.0
          },
          severity: "critical",
          for_seconds: 300
        })

      assert changeset.valid?
    end

    test "creates a valid SLO alert rule", %{project: project} do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: project.id,
          name: "SLO Burn Rate",
          rule_type: "slo",
          condition: %{
            "slo_id" => Ecto.UUID.generate(),
            "burn_rate_threshold" => 2.0
          },
          severity: "warning"
        })

      assert changeset.valid?
    end

    test "validates rule type" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Rule",
          rule_type: "invalid",
          condition: %{"metric" => "foo", "operator" => ">", "value" => 1}
        })

      assert "is invalid" in errors_on(changeset).rule_type
    end

    test "validates severity" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Severity",
          rule_type: "metric",
          condition: %{"metric" => "foo", "operator" => ">", "value" => 1},
          severity: "extreme"
        })

      assert "is invalid" in errors_on(changeset).severity
    end

    test "validates condition format" do
      changeset =
        AlertRule.changeset(%AlertRule{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Condition",
          rule_type: "metric",
          condition: %{"nonsense" => true}
        })

      assert "must contain valid metric or slo condition" in errors_on(changeset).condition
    end

    test "silenced? returns false when not silenced" do
      rule = %AlertRule{silenced_until: nil}
      refute AlertRule.silenced?(rule)
    end

    test "silenced? returns true during silence period" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second)
      rule = %AlertRule{silenced_until: future}
      assert AlertRule.silenced?(rule)
    end

    test "silenced? returns false after silence expires" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)
      rule = %AlertRule{silenced_until: past}
      refute AlertRule.silenced?(rule)
    end
  end

  describe "alert state schema" do
    test "validates state values" do
      changeset =
        AlertState.changeset(%AlertState{}, %{
          alert_rule_id: Ecto.UUID.generate(),
          state: "invalid_state"
        })

      assert "is invalid" in errors_on(changeset).state
    end

    test "accepts valid states" do
      Enum.each(AlertState.states(), fn state ->
        changeset =
          AlertState.changeset(%AlertState{}, %{
            alert_rule_id: Ecto.UUID.generate(),
            state: state
          })

        assert changeset.valid?, "State #{state} should be valid"
      end)
    end
  end

  describe "alert CRUD" do
    test "creates, lists, and deletes alert rules", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "CRUD Alert",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      assert [fetched] = Observability.list_alert_rules(project.id)
      assert fetched.id == rule.id

      {:ok, _} = Observability.delete_alert_rule(rule)
      assert [] == Observability.list_alert_rules(project.id)
    end

    test "silences and unsilences an alert rule", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Silence Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      future = DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)
      {:ok, silenced} = Observability.silence_alert_rule(rule, future)
      assert AlertRule.silenced?(silenced)

      {:ok, unsilenced} = Observability.unsilence_alert_rule(silenced)
      refute AlertRule.silenced?(unsilenced)
    end
  end

  describe "alert evaluator" do
    test "evaluate_rule transitions inactive to firing (no grace period)", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Immediate Fire",
          rule_type: "metric",
          condition: %{
            "metric" => "error_rate",
            "operator" => ">=",
            "value" => 0.0
          },
          severity: "warning",
          for_seconds: 0
        })

      # error_rate is 0.0 which is >= 0.0, so it fires
      AlertEvaluator.evaluate_rule(rule)

      states = Observability.active_alert_states(rule.id)
      assert length(states) == 1
      assert hd(states).state == "firing"
    end

    test "evaluate_rule transitions to pending with grace period", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Pending Fire",
          rule_type: "metric",
          condition: %{
            "metric" => "error_rate",
            "operator" => ">=",
            "value" => 0.0
          },
          severity: "warning",
          for_seconds: 300
        })

      AlertEvaluator.evaluate_rule(rule)

      states = Observability.active_alert_states(rule.id)
      assert length(states) == 1
      assert hd(states).state == "pending"
    end

    test "evaluate_rule resolves firing alert when condition clears", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Resolve Test",
          rule_type: "metric",
          condition: %{
            "metric" => "error_rate",
            "operator" => ">",
            "value" => 99.0
          },
          severity: "warning",
          for_seconds: 0
        })

      # Create a firing state manually
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _firing_state} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 100.0,
          fingerprint: "test"
        })
        |> Repo.insert()

      # Evaluate — error_rate is 0.0 which is NOT > 99, so condition is false
      AlertEvaluator.evaluate_rule(rule)

      # Should be resolved
      states =
        from(s in AlertState,
          where: s.alert_rule_id == ^rule.id,
          order_by: [desc: s.updated_at]
        )
        |> Repo.all()

      resolved = Enum.find(states, &(&1.state == "resolved"))
      assert resolved != nil
    end

    test "acknowledge_alert sets ack fields", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Ack Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 0.0}
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      user_id = Ecto.UUID.generate()

      {:ok, state} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 5.0,
          fingerprint: "test-ack"
        })
        |> Repo.insert()

      {:ok, acked} = Observability.acknowledge_alert(state, user_id)
      assert acked.acknowledged_by == user_id
      assert acked.acknowledged_at != nil
    end

    test "firing_alert_count returns correct count", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Count Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 0.0}
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 5.0,
          fingerprint: "count-1"
        })
        |> Repo.insert()

      assert Observability.firing_alert_count(project.id) == 1
    end
  end

  # ─── 15.4 Rollups ───────────────────────────────────────────────

  describe "metric rollup schema" do
    test "creates a valid rollup" do
      changeset =
        MetricRollup.changeset(%MetricRollup{}, %{
          service_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate(),
          period: "hourly",
          period_start: DateTime.utc_now() |> DateTime.truncate(:second),
          request_count: 1000,
          error_count: 5
        })

      assert changeset.valid?
    end

    test "validates period values" do
      changeset =
        MetricRollup.changeset(%MetricRollup{}, %{
          service_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate(),
          period: "weekly",
          period_start: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert "is invalid" in errors_on(changeset).period
    end

    test "lists valid periods" do
      assert MetricRollup.periods() == ~w(hourly daily monthly)
    end
  end

  describe "rollup worker" do
    test "rollup_hourly creates aggregated records", %{project: project} do
      service = service_fixture(project)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      hour_start = %{now | minute: 0, second: 0, microsecond: {0, 0}}
      prev_hour = DateTime.add(hour_start, -1800, :second)

      # Insert raw metric in the previous hour
      insert_metric(service.id, project.id, prev_hour, 100, 5)

      count = RollupWorker.rollup_hourly(now)
      assert count == 1

      rollups = Repo.all(MetricRollup)
      assert length(rollups) == 1
      rollup = hd(rollups)
      assert rollup.period == "hourly"
      assert rollup.request_count == 100
      assert rollup.error_count == 5
    end

    test "prune_old_metrics removes expired data", %{project: project} do
      service = service_fixture(project)

      old_time =
        DateTime.utc_now() |> DateTime.add(-10 * 86400, :second) |> DateTime.truncate(:second)

      insert_metric(service.id, project.id, old_time, 50, 2)

      count = RollupWorker.prune_old_metrics(7)
      assert count == 1
    end

    test "rollup_hourly returns 0 with no data" do
      count = RollupWorker.rollup_hourly()
      assert count == 0
    end
  end

  # ─── 15.5 New Context Functions ──────────────────────────────────

  describe "new context functions" do
    test "list_all_enabled_slos returns all enabled SLOs across projects", %{project: project} do
      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Enabled SLO",
          sli_type: "availability",
          target: 99.9,
          enabled: true
        })

      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Disabled SLO",
          sli_type: "error_rate",
          target: 1.0,
          enabled: false
        })

      enabled = Observability.list_all_enabled_slos()
      assert length(enabled) == 1
      assert hd(enabled).name == "Enabled SLO"
    end

    test "slo_summary returns counts by status", %{project: project} do
      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Healthy SLO",
          sli_type: "availability",
          target: 99.9,
          error_budget_remaining: 80.0
        })

      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Warning SLO",
          sli_type: "error_rate",
          target: 1.0,
          error_budget_remaining: 20.0
        })

      summary = Observability.slo_summary(project.id)
      assert summary.total == 2
      assert summary.healthy == 1
      assert summary.warning == 1
      assert summary.breached == 0
    end

    test "slo_status returns correct status based on budget" do
      assert Observability.slo_status(%Observability.Slo{error_budget_remaining: nil}) == :healthy

      assert Observability.slo_status(%Observability.Slo{error_budget_remaining: 80.0}) ==
               :healthy

      assert Observability.slo_status(%Observability.Slo{error_budget_remaining: 30.0}) ==
               :warning

      assert Observability.slo_status(%Observability.Slo{error_budget_remaining: 0.0}) ==
               :breached

      assert Observability.slo_status(%Observability.Slo{error_budget_remaining: -5.0}) ==
               :breached
    end

    test "get_slo! raises on missing ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Observability.get_slo!(Ecto.UUID.generate())
      end
    end

    test "get_alert_rule! raises on missing ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Observability.get_alert_rule!(Ecto.UUID.generate())
      end
    end

    test "list_firing_alerts returns active alerts with preloaded rules", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "Firing Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %AlertState{}
        |> AlertState.changeset(%{
          alert_rule_id: rule.id,
          state: "firing",
          started_at: now,
          firing_at: now,
          value: 10.0,
          fingerprint: "list-firing"
        })
        |> Repo.insert()

      alerts = Observability.list_firing_alerts(project.id)
      assert length(alerts) == 1
      assert hd(alerts).alert_rule.name == "Firing Test"
    end

    test "list_recent_alert_states returns history", %{project: project} do
      {:ok, rule} =
        Observability.create_alert_rule(%{
          project_id: project.id,
          name: "History Test",
          rule_type: "metric",
          condition: %{"metric" => "error_rate", "operator" => ">", "value" => 5.0}
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..3 do
        {:ok, _} =
          %AlertState{}
          |> AlertState.changeset(%{
            alert_rule_id: rule.id,
            state: "resolved",
            started_at: DateTime.add(now, -i * 60, :second),
            value: 10.0 + i,
            fingerprint: "history-#{i}"
          })
          |> Repo.insert()
      end

      states = Observability.list_recent_alert_states(rule.id, limit: 2)
      assert length(states) == 2
    end
  end

  describe "SLI worker" do
    test "perform computes all enabled SLOs", %{project: project} do
      {:ok, _} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Worker SLO",
          sli_type: "availability",
          target: 99.9
        })

      assert :ok == ZentinelCp.Observability.SliWorker.perform(%Oban.Job{})

      slo = hd(Observability.list_slos(project.id))
      assert slo.last_computed_at != nil
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────

  defp service_fixture(project) do
    name = "test-svc-#{System.unique_integer([:positive])}"

    {:ok, service} =
      %ZentinelCp.Services.Service{}
      |> Ecto.Changeset.change(%{
        project_id: project.id,
        name: name,
        slug: name,
        route_path: "/#{name}"
      })
      |> Repo.insert()

    service
  end

  defp insert_metric(service_id, project_id, period_start, request_count, error_count) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(ServiceMetric, [
      %{
        id: Ecto.UUID.generate(),
        service_id: service_id,
        project_id: project_id,
        period_start: period_start,
        period_seconds: 60,
        request_count: request_count,
        error_count: error_count,
        latency_p50_ms: 10,
        latency_p95_ms: 50,
        latency_p99_ms: 100,
        bandwidth_in_bytes: 1000,
        bandwidth_out_bytes: 5000,
        status_2xx: request_count - error_count,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: error_count,
        top_paths: %{},
        top_consumers: %{},
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
