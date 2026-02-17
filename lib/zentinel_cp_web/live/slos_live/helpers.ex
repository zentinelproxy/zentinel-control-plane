defmodule ZentinelCpWeb.SlosLive.Helpers do
  @moduledoc """
  Shared path helpers and components for SLO and Alert LiveViews.
  """
  use Phoenix.Component
  use ZentinelCpWeb, :verified_routes

  alias ZentinelCp.Orgs

  # -- resolve_org --

  def resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  def resolve_org(_), do: nil

  # -- Status Helpers --

  attr :status, :atom, required: true

  def slo_status_badge(assigns) do
    {color, label} =
      case assigns.status do
        :healthy -> {"badge-success", "Healthy"}
        :warning -> {"badge-warning", "Warning"}
        :breached -> {"badge-error", "Breached"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span class={["badge badge-sm", @color]}>{@label}</span>
    """
  end

  attr :severity, :string, required: true

  def severity_badge(assigns) do
    color =
      case assigns.severity do
        "critical" -> "badge-error"
        "warning" -> "badge-warning"
        "info" -> "badge-info"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-sm", @color]}>{@severity}</span>
    """
  end

  attr :state, :string, required: true

  def alert_state_badge(assigns) do
    color =
      case assigns.state do
        "firing" -> "badge-error"
        "pending" -> "badge-warning"
        "resolved" -> "badge-success"
        "inactive" -> "badge-ghost"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-sm", @color]}>{@state}</span>
    """
  end

  # -- SLO Path Helpers --

  def slos_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/slos"

  def slos_path(nil, project),
    do: ~p"/projects/#{project.slug}/slos"

  def new_slo_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/slos/new"

  def new_slo_path(nil, project),
    do: ~p"/projects/#{project.slug}/slos/new"

  def slo_path(%{slug: org_slug}, project, slo),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/slos/#{slo.id}"

  def slo_path(nil, project, slo),
    do: ~p"/projects/#{project.slug}/slos/#{slo.id}"

  def edit_slo_path(%{slug: org_slug}, project, slo),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/slos/#{slo.id}/edit"

  def edit_slo_path(nil, project, slo),
    do: ~p"/projects/#{project.slug}/slos/#{slo.id}/edit"

  # -- Alert Path Helpers --

  def alerts_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/alerts"

  def alerts_path(nil, project),
    do: ~p"/projects/#{project.slug}/alerts"

  def alert_rules_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/alerts/rules"

  def alert_rules_path(nil, project),
    do: ~p"/projects/#{project.slug}/alerts/rules"

  def new_alert_rule_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/alerts/rules/new"

  def new_alert_rule_path(nil, project),
    do: ~p"/projects/#{project.slug}/alerts/rules/new"

  def alert_rule_path(%{slug: org_slug}, project, rule),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/alerts/rules/#{rule.id}"

  def alert_rule_path(nil, project, rule),
    do: ~p"/projects/#{project.slug}/alerts/rules/#{rule.id}"

  def edit_alert_rule_path(%{slug: org_slug}, project, rule),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/alerts/rules/#{rule.id}/edit"

  def edit_alert_rule_path(nil, project, rule),
    do: ~p"/projects/#{project.slug}/alerts/rules/#{rule.id}/edit"

  # -- Alert Tabs --

  attr :org, :any, required: true
  attr :project, :any, required: true
  attr :active, :string, required: true

  def alert_tabs(assigns) do
    ~H"""
    <div class="tabs tabs-bordered">
      <.link
        navigate={alerts_path(@org, @project)}
        class={["tab", @active == "active" && "tab-active"]}
      >
        Active Alerts
      </.link>
      <.link
        navigate={alert_rules_path(@org, @project)}
        class={["tab", @active == "rules" && "tab-active"]}
      >
        Rules
      </.link>
    </div>
    """
  end
end
