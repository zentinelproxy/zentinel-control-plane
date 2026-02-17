defmodule ZentinelCp.PoliciesTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Policies
  alias ZentinelCp.Policies.{Policy, Violation, Evaluator}
  alias ZentinelCp.Audit.ComplianceExport

  import ZentinelCp.ProjectsFixtures

  setup do
    project = project_fixture()
    %{project: project}
  end

  # ─── 16.1 Policy Schema ─────────────────────────────────────────

  describe "policy schema" do
    test "creates a valid deployment policy", %{project: project} do
      changeset =
        Policy.changeset(%Policy{}, %{
          project_id: project.id,
          name: "No Friday Deploys",
          policy_type: "deployment",
          expression: ~s(day_of_week != "friday"),
          severity: "warning"
        })

      assert changeset.valid?
    end

    test "creates a valid configuration policy", %{project: project} do
      changeset =
        Policy.changeset(%Policy{}, %{
          project_id: project.id,
          name: "Require Rate Limiting",
          policy_type: "configuration",
          expression: "has_rate_limit == true",
          severity: "critical"
        })

      assert changeset.valid?
    end

    test "validates policy type" do
      changeset =
        Policy.changeset(%Policy{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Type",
          policy_type: "invalid",
          expression: "foo == true"
        })

      assert "is invalid" in errors_on(changeset).policy_type
    end

    test "validates enforcement mode" do
      changeset =
        Policy.changeset(%Policy{}, %{
          project_id: Ecto.UUID.generate(),
          name: "Bad Enforcement",
          policy_type: "deployment",
          expression: "foo == true",
          enforcement: "yolo"
        })

      assert "is invalid" in errors_on(changeset).enforcement
    end

    test "validates expression syntax" do
      changeset =
        Policy.changeset(%Policy{}, %{
          project_id: Ecto.UUID.generate(),
          name: "No Operator",
          policy_type: "deployment",
          expression: "just some text"
        })

      assert "contains invalid syntax" in errors_on(changeset).expression
    end

    test "lists policy types" do
      assert Policy.policy_types() == ~w(deployment configuration access)
    end
  end

  # ─── 16.1 Expression Evaluator ──────────────────────────────────

  describe "expression evaluator" do
    test "evaluates equality" do
      assert Evaluator.evaluate(~s(strategy == "rolling"), %{"strategy" => "rolling"}) ==
               {:ok, true}

      assert Evaluator.evaluate(~s(strategy == "canary"), %{"strategy" => "rolling"}) ==
               {:ok, false}
    end

    test "evaluates inequality" do
      assert Evaluator.evaluate(~s(day_of_week != "friday"), %{"day_of_week" => "monday"}) ==
               {:ok, true}

      assert Evaluator.evaluate(~s(day_of_week != "friday"), %{"day_of_week" => "friday"}) ==
               {:ok, false}
    end

    test "evaluates numeric comparisons" do
      assert Evaluator.evaluate("approvals >= 2", %{"approvals" => 3}) == {:ok, true}
      assert Evaluator.evaluate("approvals >= 2", %{"approvals" => 1}) == {:ok, false}
      assert Evaluator.evaluate("error_rate < 5.0", %{"error_rate" => 3.2}) == {:ok, true}
      assert Evaluator.evaluate("latency > 100", %{"latency" => 150}) == {:ok, true}
      assert Evaluator.evaluate("count <= 10", %{"count" => 10}) == {:ok, true}
    end

    test "evaluates boolean equality" do
      assert Evaluator.evaluate("has_rate_limit == true", %{"has_rate_limit" => true}) ==
               {:ok, true}

      assert Evaluator.evaluate("has_rate_limit == true", %{"has_rate_limit" => false}) ==
               {:ok, false}
    end

    test "evaluates 'in' operator" do
      assert Evaluator.evaluate(
               ~s(strategy in ["rolling", "canary"]),
               %{"strategy" => "rolling"}
             ) == {:ok, true}

      assert Evaluator.evaluate(
               ~s(strategy in ["rolling", "canary"]),
               %{"strategy" => "blue_green"}
             ) == {:ok, false}
    end

    test "evaluates 'not_in' operator" do
      assert Evaluator.evaluate(
               ~s(env not_in ["production", "staging"]),
               %{"env" => "development"}
             ) == {:ok, true}

      assert Evaluator.evaluate(
               ~s(env not_in ["production", "staging"]),
               %{"env" => "production"}
             ) == {:ok, false}
    end

    test "evaluates 'contains' operator" do
      assert Evaluator.evaluate(
               ~s(path contains "api"),
               %{"path" => "/api/v1/users"}
             ) == {:ok, true}
    end

    test "evaluates AND expressions" do
      expr = ~s(approvals >= 2 && strategy == "rolling")
      assert Evaluator.evaluate(expr, %{"approvals" => 3, "strategy" => "rolling"}) == {:ok, true}

      assert Evaluator.evaluate(expr, %{"approvals" => 1, "strategy" => "rolling"}) ==
               {:ok, false}
    end

    test "evaluates OR expressions" do
      expr = ~s(env == "staging" || env == "development")
      assert Evaluator.evaluate(expr, %{"env" => "staging"}) == {:ok, true}
      assert Evaluator.evaluate(expr, %{"env" => "development"}) == {:ok, true}
      assert Evaluator.evaluate(expr, %{"env" => "production"}) == {:ok, false}
    end

    test "handles atom keys in context" do
      assert Evaluator.evaluate("strategy == \"rolling\"", %{strategy: "rolling"}) == {:ok, true}
    end

    test "returns error for invalid expression" do
      assert {:error, _} = Evaluator.evaluate("gibberish", %{})
    end
  end

  # ─── 16.1 Policy Evaluation ─────────────────────────────────────

  describe "policy evaluation" do
    test "enforce mode blocks on violation", %{project: project} do
      {:ok, _policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "No Blue-Green",
          policy_type: "deployment",
          expression: ~s(strategy != "blue_green"),
          enforcement: "enforce"
        })

      context = %{
        "strategy" => "blue_green",
        "resource_type" => "rollout",
        "action" => "create"
      }

      assert {:error, {:policy_violation, messages}} =
               Policies.evaluate(project.id, "deployment", context)

      assert length(messages) == 1
      assert hd(messages) =~ "No Blue-Green"
    end

    test "dry_run mode logs but doesn't block", %{project: project} do
      {:ok, _policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Dry Run Policy",
          policy_type: "deployment",
          expression: ~s(strategy != "all_at_once"),
          enforcement: "dry_run"
        })

      context = %{
        "strategy" => "all_at_once",
        "resource_type" => "rollout",
        "action" => "create"
      }

      assert {:ok, violations} = Policies.evaluate(project.id, "deployment", context)
      assert length(violations) == 1
    end

    test "passing policies return empty violations", %{project: project} do
      {:ok, _policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Allow Rolling",
          policy_type: "deployment",
          expression: ~s(strategy == "rolling"),
          enforcement: "enforce"
        })

      context = %{
        "strategy" => "rolling",
        "resource_type" => "rollout",
        "action" => "create"
      }

      assert {:ok, []} = Policies.evaluate(project.id, "deployment", context)
    end

    test "evaluate_dry_run never blocks", %{project: project} do
      {:ok, _policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Strict Policy",
          policy_type: "deployment",
          expression: "approvals >= 2",
          enforcement: "enforce"
        })

      context = %{
        "approvals" => 0,
        "resource_type" => "rollout",
        "action" => "create"
      }

      assert {:ok, violations} = Policies.evaluate_dry_run(project.id, "deployment", context)
      assert length(violations) == 1
    end

    test "disabled policies are not evaluated", %{project: project} do
      {:ok, policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Disabled Policy",
          policy_type: "deployment",
          expression: "approvals >= 100",
          enforcement: "enforce"
        })

      Policies.update_policy(policy, %{enabled: false})

      context = %{"approvals" => 0, "resource_type" => "rollout", "action" => "create"}
      assert {:ok, []} = Policies.evaluate(project.id, "deployment", context)
    end
  end

  # ─── 16.1 Policy CRUD ───────────────────────────────────────────

  describe "policy CRUD" do
    test "creates, lists, and deletes policies", %{project: project} do
      {:ok, policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "CRUD Policy",
          policy_type: "configuration",
          expression: "has_rate_limit == true"
        })

      assert [fetched] = Policies.list_policies(project.id)
      assert fetched.id == policy.id

      {:ok, _} = Policies.delete_policy(policy)
      assert [] == Policies.list_policies(project.id)
    end

    test "updates a policy", %{project: project} do
      {:ok, policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Update Policy",
          policy_type: "deployment",
          expression: "approvals >= 1"
        })

      {:ok, updated} = Policies.update_policy(policy, %{expression: "approvals >= 2"})
      assert updated.expression == "approvals >= 2"
    end

    test "lists violations", %{project: project} do
      {:ok, _policy} =
        Policies.create_policy(%{
          project_id: project.id,
          name: "Violation Test",
          policy_type: "deployment",
          expression: "approvals >= 10",
          enforcement: "dry_run"
        })

      Policies.evaluate(project.id, "deployment", %{
        "approvals" => 0,
        "resource_type" => "rollout",
        "action" => "create"
      })

      violations = Policies.list_violations(project.id)
      assert length(violations) == 1
      assert hd(violations).resource_type == "rollout"
    end
  end

  # ─── 16.2 Compliance Export ──────────────────────────────────────

  describe "compliance export" do
    test "exports in CEF format", %{project: project} do
      # Create an audit log entry
      ZentinelCp.Audit.log(%{
        action: "rollout.created",
        actor_type: "user",
        actor_id: Ecto.UUID.generate(),
        resource_type: "rollout",
        resource_id: Ecto.UUID.generate(),
        project_id: project.id,
        metadata: %{"strategy" => "rolling"}
      })

      output = ComplianceExport.export(project.id, "cef")
      assert is_binary(output)
      assert output =~ "CEF:0|ZentinelCP|ControlPlane"
      assert output =~ "rollout.created"
    end

    test "exports in LEEF format", %{project: project} do
      ZentinelCp.Audit.log(%{
        action: "bundle.compiled",
        actor_type: "system",
        resource_type: "bundle",
        resource_id: Ecto.UUID.generate(),
        project_id: project.id
      })

      output = ComplianceExport.export(project.id, "leef")
      assert is_binary(output)
      assert output =~ "LEEF:2.0|ZentinelCP|ControlPlane"
      assert output =~ "bundle.compiled"
    end

    test "exports in JSON Lines format", %{project: project} do
      ZentinelCp.Audit.log(%{
        action: "node.registered",
        actor_type: "node",
        actor_id: Ecto.UUID.generate(),
        resource_type: "node",
        resource_id: Ecto.UUID.generate(),
        project_id: project.id
      })

      output = ComplianceExport.export(project.id, "json_lines")
      assert is_binary(output)

      # Each line should be valid JSON
      lines = String.split(output, "\n", trim: true)
      assert length(lines) >= 1
      assert {:ok, decoded} = Jason.decode(hd(lines))
      assert decoded["action"] == "node.registered"
      assert decoded["source"] == "zentinel_cp"
    end

    test "returns empty string for no logs", %{project: project} do
      output = ComplianceExport.export(project.id, "json_lines")
      assert output == ""
    end
  end

  # ─── Violation schema ───────────────────────────────────────────

  describe "violation schema" do
    test "creates a valid violation changeset" do
      changeset =
        Violation.changeset(%Violation{}, %{
          policy_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate(),
          resource_type: "rollout",
          action: "create",
          message: "Policy violated"
        })

      assert changeset.valid?
    end
  end
end
