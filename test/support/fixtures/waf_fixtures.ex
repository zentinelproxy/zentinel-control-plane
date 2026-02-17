defmodule ZentinelCp.WafFixtures do
  @moduledoc """
  Test helpers for creating WAF entities (rules, policies, overrides).
  """

  alias ZentinelCp.Repo
  alias ZentinelCp.Waf
  alias ZentinelCp.Waf.WafRule

  def unique_rule_id, do: "TEST-#{System.unique_integer([:positive])}"
  def unique_policy_name, do: "waf-policy-#{System.unique_integer([:positive])}"

  def waf_rule_fixture(attrs \\ %{}) do
    {:ok, rule} =
      %WafRule{}
      |> WafRule.create_changeset(%{
        rule_id: attrs[:rule_id] || unique_rule_id(),
        name: attrs[:name] || "Test WAF Rule",
        description: attrs[:description] || "A test rule",
        category: attrs[:category] || "sqli",
        severity: attrs[:severity] || "high",
        default_action: attrs[:default_action] || "block",
        targets: attrs[:targets] || ["args", "body"],
        tags: attrs[:tags] || ["test"],
        is_builtin: Map.get(attrs, :is_builtin, false),
        phase: attrs[:phase] || "request"
      })
      |> Repo.insert()

    rule
  end

  def waf_policy_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, policy} =
      Waf.create_policy(%{
        name: attrs[:name] || unique_policy_name(),
        description: attrs[:description] || "A test WAF policy",
        mode: attrs[:mode] || "block",
        sensitivity: attrs[:sensitivity] || "medium",
        enabled_categories: attrs[:enabled_categories] || ["sqli", "xss"],
        default_action: attrs[:default_action] || "block",
        max_body_size: attrs[:max_body_size],
        max_header_size: attrs[:max_header_size],
        max_uri_length: attrs[:max_uri_length],
        project_id: project.id
      })

    policy
  end
end
