defmodule ZentinelCp.Waf.WafRuleTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Waf.WafRule

  describe "create_changeset/2" do
    test "valid attrs" do
      changeset =
        WafRule.create_changeset(%WafRule{}, %{
          rule_id: "TEST-001",
          name: "Test Rule",
          category: "sqli",
          severity: "high",
          default_action: "block"
        })

      assert changeset.valid?
    end

    test "requires rule_id, name, category" do
      changeset = WafRule.create_changeset(%WafRule{}, %{})
      refute changeset.valid?
      assert %{rule_id: _, name: _, category: _} = errors_on(changeset)
    end

    test "validates category inclusion" do
      changeset =
        WafRule.create_changeset(%WafRule{}, %{
          rule_id: "TEST-002",
          name: "Bad Category",
          category: "invalid"
        })

      refute changeset.valid?
      assert %{category: _} = errors_on(changeset)
    end

    test "validates severity inclusion" do
      changeset =
        WafRule.create_changeset(%WafRule{}, %{
          rule_id: "TEST-003",
          name: "Bad Severity",
          category: "sqli",
          severity: "extreme"
        })

      refute changeset.valid?
      assert %{severity: _} = errors_on(changeset)
    end

    test "validates phase inclusion" do
      changeset =
        WafRule.create_changeset(%WafRule{}, %{
          rule_id: "TEST-004",
          name: "Bad Phase",
          category: "sqli",
          phase: "neither"
        })

      refute changeset.valid?
      assert %{phase: _} = errors_on(changeset)
    end

    test "enforces unique rule_id" do
      {:ok, _} =
        %WafRule{}
        |> WafRule.create_changeset(%{
          rule_id: "DUP-001",
          name: "First",
          category: "sqli"
        })
        |> ZentinelCp.Repo.insert()

      {:error, changeset} =
        %WafRule{}
        |> WafRule.create_changeset(%{
          rule_id: "DUP-001",
          name: "Duplicate",
          category: "xss"
        })
        |> ZentinelCp.Repo.insert()

      assert %{rule_id: _} = errors_on(changeset)
    end
  end
end
