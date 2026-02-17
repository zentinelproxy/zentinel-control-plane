defmodule ZentinelCp.WafTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Waf
  alias ZentinelCp.WafFixtures

  describe "list_rules/1" do
    test "returns all rules ordered by category and rule_id" do
      rules = Waf.list_rules()
      # Built-in rules should be seeded
      assert rules != []

      # Check ordering
      categories = Enum.map(rules, & &1.category)
      assert categories == Enum.sort(categories)
    end

    test "filters by category" do
      rules = Waf.list_rules(category: "sqli")
      assert Enum.all?(rules, fn r -> r.category == "sqli" end)
    end

    test "filters by severity" do
      rules = Waf.list_rules(severity: "critical")
      assert Enum.all?(rules, fn r -> r.severity == "critical" end)
    end

    test "filters by search term" do
      rules = Waf.list_rules(search: "CRS-942100")
      assert length(rules) >= 1
      assert Enum.any?(rules, fn r -> r.rule_id == "CRS-942100" end)
    end
  end

  describe "policies CRUD" do
    test "create_policy/1 with valid attrs" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      {:ok, policy} =
        Waf.create_policy(%{
          name: "My WAF Policy",
          mode: "block",
          sensitivity: "high",
          enabled_categories: ["sqli", "xss"],
          default_action: "block",
          project_id: project.id
        })

      assert policy.name == "My WAF Policy"
      assert policy.slug == "my-waf-policy"
      assert policy.mode == "block"
      assert policy.sensitivity == "high"
      assert policy.enabled_categories == ["sqli", "xss"]
    end

    test "create_policy/1 with invalid mode fails" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      {:error, changeset} =
        Waf.create_policy(%{
          name: "Bad Policy",
          mode: "invalid_mode",
          sensitivity: "medium",
          project_id: project.id
        })

      assert %{mode: _} = errors_on(changeset)
    end

    test "create_policy/1 enforces unique slug per project" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      {:ok, _} =
        Waf.create_policy(%{
          name: "Duplicate",
          mode: "block",
          sensitivity: "medium",
          project_id: project.id
        })

      {:error, changeset} =
        Waf.create_policy(%{
          name: "Duplicate",
          mode: "block",
          sensitivity: "medium",
          project_id: project.id
        })

      assert %{slug: _} = errors_on(changeset)
    end

    test "update_policy/2" do
      policy = WafFixtures.waf_policy_fixture()

      {:ok, updated} = Waf.update_policy(policy, %{mode: "detect_only"})
      assert updated.mode == "detect_only"
    end

    test "delete_policy/1" do
      policy = WafFixtures.waf_policy_fixture()
      {:ok, _} = Waf.delete_policy(policy)
      assert Waf.get_policy(policy.id) == nil
    end

    test "list_policies/1 returns project policies" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()
      WafFixtures.waf_policy_fixture(%{project: project, name: "Policy A"})
      WafFixtures.waf_policy_fixture(%{project: project, name: "Policy B"})

      policies = Waf.list_policies(project.id)
      assert length(policies) == 2
      names = Enum.map(policies, & &1.name)
      assert "Policy A" in names
      assert "Policy B" in names
    end
  end

  describe "rule overrides" do
    test "upsert_override/1 creates an override" do
      policy = WafFixtures.waf_policy_fixture()
      rule = WafFixtures.waf_rule_fixture()

      {:ok, override} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: rule.id,
          action: "log",
          note: "Testing"
        })

      assert override.action == "log"
      assert override.note == "Testing"
    end

    test "upsert_override/1 updates existing override" do
      policy = WafFixtures.waf_policy_fixture()
      rule = WafFixtures.waf_rule_fixture()

      {:ok, _} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: rule.id,
          action: "log"
        })

      {:ok, updated} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: rule.id,
          action: "block"
        })

      assert updated.action == "block"

      # Should still be only 1 override
      overrides = Waf.list_overrides(policy.id)
      assert length(overrides) == 1
    end

    test "delete_override/1 removes an override" do
      policy = WafFixtures.waf_policy_fixture()
      rule = WafFixtures.waf_rule_fixture()

      {:ok, override} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: rule.id,
          action: "log"
        })

      {:ok, _} = Waf.delete_override(override)
      assert Waf.list_overrides(policy.id) == []
    end
  end

  describe "get_effective_rules/1" do
    test "returns rules from enabled categories" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      policy =
        WafFixtures.waf_policy_fixture(%{
          project: project,
          enabled_categories: ["sqli"]
        })

      effective = Waf.get_effective_rules(policy)
      assert effective != []
      assert Enum.all?(effective, fn {rule, _action} -> rule.category == "sqli" end)
    end

    test "returns empty list when no categories enabled" do
      policy = WafFixtures.waf_policy_fixture(%{enabled_categories: []})
      assert Waf.get_effective_rules(policy) == []
    end

    test "uses policy default_action when no override" do
      policy =
        WafFixtures.waf_policy_fixture(%{default_action: "log", enabled_categories: ["sqli"]})

      effective = Waf.get_effective_rules(policy)
      assert Enum.all?(effective, fn {_rule, action} -> action == "log" end)
    end

    test "per-rule override takes precedence" do
      policy =
        WafFixtures.waf_policy_fixture(%{
          default_action: "block",
          enabled_categories: ["sqli"]
        })

      # Get the first sqli rule
      [first_rule | _] = Waf.list_rules(category: "sqli")

      {:ok, _} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: first_rule.id,
          action: "log"
        })

      effective = Waf.get_effective_rules(policy)

      # Find the overridden rule
      {_, action} = Enum.find(effective, fn {r, _} -> r.id == first_rule.id end)
      assert action == "log"
    end

    test "disable override excludes rule" do
      policy =
        WafFixtures.waf_policy_fixture(%{
          default_action: "block",
          enabled_categories: ["sqli"]
        })

      [first_rule | _] = Waf.list_rules(category: "sqli")

      {:ok, _} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: first_rule.id,
          action: "disable"
        })

      effective = Waf.get_effective_rules(policy)
      refute Enum.any?(effective, fn {r, _} -> r.id == first_rule.id end)
    end

    test "accepts policy ID string" do
      policy = WafFixtures.waf_policy_fixture(%{enabled_categories: ["sqli"]})
      effective = Waf.get_effective_rules(policy.id)
      assert effective != []
    end
  end

  describe "delete cascade" do
    test "deleting policy cascades to overrides" do
      policy = WafFixtures.waf_policy_fixture()
      rule = WafFixtures.waf_rule_fixture()

      {:ok, _} =
        Waf.upsert_override(%{
          waf_policy_id: policy.id,
          waf_rule_id: rule.id,
          action: "log"
        })

      {:ok, _} = Waf.delete_policy(policy)
      assert Waf.list_overrides(policy.id) == []
    end
  end
end
