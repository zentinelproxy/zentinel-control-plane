defmodule ZentinelCp.Waf.BuiltInRules do
  @moduledoc """
  Built-in WAF rules based on OWASP Core Rule Set (CRS) patterns.

  Provides ~60 rules organized by category. No regex patterns are stored here —
  the Zentinel proxy handles actual detection. Rules define metadata for
  policy management and UI display.

  Call `ensure_built_ins!/0` to upsert missing rules into the database.
  """

  alias ZentinelCp.Repo
  alias ZentinelCp.Waf.WafRule
  import Ecto.Query

  @rules [
    # ── SQL Injection (sqli) ──────────────────────────────────────
    %{
      rule_id: "CRS-942100",
      name: "SQL Injection Attack Detected via libinjection",
      category: "sqli",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body", "cookies"],
      tags: ["owasp", "sqli", "a03"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942110",
      name: "SQL Injection Attack: Common Injection Testing",
      category: "sqli",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942120",
      name: "SQL Injection Attack: SQL Operator Detected",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942130",
      name: "SQL Injection Attack: SQL Tautology Detected",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942140",
      name: "SQL Injection Attack: Common DB Names Detected",
      category: "sqli",
      severity: "medium",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942150",
      name: "SQL Injection Attack: UNION-based",
      category: "sqli",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942160",
      name: "SQL Injection Attack: Blind SQL Testing (sleep/benchmark)",
      category: "sqli",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942170",
      name: "SQL Injection: Stacked Queries Detected",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942180",
      name: "SQL Injection: Basic Authentication Bypass",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942190",
      name: "SQL Injection: MSSQL Code Execution",
      category: "sqli",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942200",
      name: "SQL Injection: MySQL Comment/Obfuscation",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },
    %{
      rule_id: "CRS-942210",
      name: "SQL Injection: Chained Injection Attempt",
      category: "sqli",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "sqli"],
      phase: "request"
    },

    # ── Cross-Site Scripting (xss) ────────────────────────────────
    %{
      rule_id: "CRS-941100",
      name: "XSS Attack Detected via libinjection",
      category: "xss",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body", "headers"],
      tags: ["owasp", "xss", "a07"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941110",
      name: "XSS Filter: Script Tag Vector",
      category: "xss",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941120",
      name: "XSS Filter: Event Handler Vector",
      category: "xss",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941130",
      name: "XSS Filter: Attribute Injection",
      category: "xss",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941140",
      name: "XSS Filter: JavaScript URI Vector",
      category: "xss",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941150",
      name: "XSS Filter: DOM-based Vectors",
      category: "xss",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941160",
      name: "XSS: Encoded Payload Detection",
      category: "xss",
      severity: "medium",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941170",
      name: "XSS: SVG/MathML Tag Injection",
      category: "xss",
      severity: "medium",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941180",
      name: "XSS: Template Injection (SSTI)",
      category: "xss",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },
    %{
      rule_id: "CRS-941190",
      name: "XSS: IE-specific Conditional Comment",
      category: "xss",
      severity: "medium",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "xss"],
      phase: "request"
    },

    # ── Local File Inclusion (lfi) ────────────────────────────────
    %{
      rule_id: "CRS-930100",
      name: "Path Traversal Attack (/../)",
      category: "lfi",
      severity: "critical",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi", "a01"],
      phase: "request"
    },
    %{
      rule_id: "CRS-930110",
      name: "Path Traversal: OS File Access",
      category: "lfi",
      severity: "critical",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-930120",
      name: "Path Traversal: Restricted File Access",
      category: "lfi",
      severity: "high",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-930130",
      name: "Path Traversal: Null Byte Injection",
      category: "lfi",
      severity: "critical",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-930140",
      name: "Path Traversal: Backslash Evasion",
      category: "lfi",
      severity: "high",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-930150",
      name: "Path Traversal: URL-encoded Bypass",
      category: "lfi",
      severity: "high",
      default_action: "block",
      targets: ["uri", "args"],
      tags: ["owasp", "lfi"],
      phase: "request"
    },

    # ── Remote File Inclusion (rfi) ───────────────────────────────
    %{
      rule_id: "CRS-931100",
      name: "Remote File Inclusion: URL Parameter",
      category: "rfi",
      severity: "critical",
      default_action: "block",
      targets: ["args"],
      tags: ["owasp", "rfi", "a10"],
      phase: "request"
    },
    %{
      rule_id: "CRS-931110",
      name: "Remote File Inclusion: Common Variable Names",
      category: "rfi",
      severity: "high",
      default_action: "block",
      targets: ["args"],
      tags: ["owasp", "rfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-931120",
      name: "Remote File Inclusion: Data Scheme Detected",
      category: "rfi",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-931130",
      name: "Remote File Inclusion: Off-Domain Reference",
      category: "rfi",
      severity: "medium",
      default_action: "block",
      targets: ["args"],
      tags: ["owasp", "rfi"],
      phase: "request"
    },
    %{
      rule_id: "CRS-931140",
      name: "Remote File Inclusion: PHP Wrappers",
      category: "rfi",
      severity: "critical",
      default_action: "block",
      targets: ["args"],
      tags: ["owasp", "rfi"],
      phase: "request"
    },

    # ── Remote Code Execution (rce) ───────────────────────────────
    %{
      rule_id: "CRS-932100",
      name: "RCE: Unix Command Injection",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce", "a03"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932110",
      name: "RCE: Windows Command Injection",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932120",
      name: "RCE: PowerShell Command Detected",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932130",
      name: "RCE: Unix Shell Expression Detected",
      category: "rce",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932140",
      name: "RCE: Unix Command Chaining",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932150",
      name: "RCE: Direct Unix Command",
      category: "rce",
      severity: "high",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932160",
      name: "RCE: Code Injection Detected",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["args", "body"],
      tags: ["owasp", "rce"],
      phase: "request"
    },
    %{
      rule_id: "CRS-932170",
      name: "RCE: Shellshock (CVE-2014-6271)",
      category: "rce",
      severity: "critical",
      default_action: "block",
      targets: ["headers", "args"],
      tags: ["owasp", "rce", "cve"],
      phase: "request"
    },

    # ── Scanner Detection ─────────────────────────────────────────
    %{
      rule_id: "CRS-913100",
      name: "Scanner: Known Vulnerability Scanner UA",
      category: "scanner",
      severity: "medium",
      default_action: "block",
      targets: ["headers"],
      tags: ["owasp", "scanner", "automation"],
      phase: "request"
    },
    %{
      rule_id: "CRS-913110",
      name: "Scanner: Known Scripting/Bot UA",
      category: "scanner",
      severity: "medium",
      default_action: "block",
      targets: ["headers"],
      tags: ["owasp", "scanner"],
      phase: "request"
    },
    %{
      rule_id: "CRS-913120",
      name: "Scanner: Known Crawler UA",
      category: "scanner",
      severity: "low",
      default_action: "log",
      targets: ["headers"],
      tags: ["owasp", "scanner"],
      phase: "request"
    },
    %{
      rule_id: "CRS-913130",
      name: "Scanner: Empty or Missing User-Agent",
      category: "scanner",
      severity: "low",
      default_action: "log",
      targets: ["headers"],
      tags: ["owasp", "scanner"],
      phase: "request"
    },
    %{
      rule_id: "CRS-913140",
      name: "Scanner: Known Security Tool Request Patterns",
      category: "scanner",
      severity: "medium",
      default_action: "block",
      targets: ["uri", "headers"],
      tags: ["owasp", "scanner"],
      phase: "request"
    },
    %{
      rule_id: "CRS-913150",
      name: "Scanner: Suspicious HTTP Method",
      category: "scanner",
      severity: "medium",
      default_action: "log",
      targets: ["method"],
      tags: ["owasp", "scanner"],
      phase: "request"
    },

    # ── Protocol Violations ───────────────────────────────────────
    %{
      rule_id: "CRS-920100",
      name: "Protocol: Invalid HTTP Request Line",
      category: "protocol",
      severity: "high",
      default_action: "block",
      targets: ["request_line"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920110",
      name: "Protocol: Multipart Request Body Too Large",
      category: "protocol",
      severity: "medium",
      default_action: "block",
      targets: ["body"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920120",
      name: "Protocol: Request Content-Type Not Allowed",
      category: "protocol",
      severity: "medium",
      default_action: "block",
      targets: ["headers"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920130",
      name: "Protocol: Failed to Parse Request Body",
      category: "protocol",
      severity: "medium",
      default_action: "block",
      targets: ["body"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920140",
      name: "Protocol: Missing Content-Type Header",
      category: "protocol",
      severity: "low",
      default_action: "log",
      targets: ["headers"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920150",
      name: "Protocol: Request URI Too Long",
      category: "protocol",
      severity: "medium",
      default_action: "block",
      targets: ["uri"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920160",
      name: "Protocol: Content-Length Mismatch",
      category: "protocol",
      severity: "high",
      default_action: "block",
      targets: ["headers", "body"],
      tags: ["owasp", "protocol"],
      phase: "request"
    },
    %{
      rule_id: "CRS-920170",
      name: "Protocol: Transfer-Encoding Abuse",
      category: "protocol",
      severity: "critical",
      default_action: "block",
      targets: ["headers"],
      tags: ["owasp", "protocol", "smuggling"],
      phase: "request"
    },

    # ── Data Leak Prevention ──────────────────────────────────────
    %{
      rule_id: "CRS-950100",
      name: "Data Leak: Credit Card Number in Response",
      category: "data_leak",
      severity: "critical",
      default_action: "block",
      targets: ["response_body"],
      tags: ["owasp", "data_leak", "pci"],
      phase: "response"
    },
    %{
      rule_id: "CRS-950110",
      name: "Data Leak: SSN Pattern in Response",
      category: "data_leak",
      severity: "critical",
      default_action: "block",
      targets: ["response_body"],
      tags: ["owasp", "data_leak", "pii"],
      phase: "response"
    },
    %{
      rule_id: "CRS-950120",
      name: "Data Leak: SQL Error Message Exposure",
      category: "data_leak",
      severity: "high",
      default_action: "block",
      targets: ["response_body"],
      tags: ["owasp", "data_leak", "information_disclosure"],
      phase: "response"
    },
    %{
      rule_id: "CRS-950130",
      name: "Data Leak: Application Stack Trace",
      category: "data_leak",
      severity: "high",
      default_action: "block",
      targets: ["response_body"],
      tags: ["owasp", "data_leak", "information_disclosure"],
      phase: "response"
    },
    %{
      rule_id: "CRS-950140",
      name: "Data Leak: Directory Listing Detected",
      category: "data_leak",
      severity: "medium",
      default_action: "log",
      targets: ["response_body"],
      tags: ["owasp", "data_leak"],
      phase: "response"
    }
  ]

  @doc """
  Returns the list of built-in rule definitions (raw maps).
  """
  def rules, do: @rules

  @doc """
  Ensures built-in WAF rules exist in the database.
  Uses insert-if-missing semantics — existing rules are not updated.
  Safe to call multiple times.
  """
  def ensure_built_ins! do
    existing_rule_ids =
      from(r in WafRule, where: r.is_builtin == true, select: r.rule_id)
      |> Repo.all()
      |> MapSet.new()

    Enum.each(@rules, fn rule_attrs ->
      unless MapSet.member?(existing_rule_ids, rule_attrs.rule_id) do
        %WafRule{}
        |> WafRule.create_changeset(rule_attrs)
        |> Repo.insert!()
      end
    end)

    :ok
  end
end
