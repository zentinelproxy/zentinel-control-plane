defmodule SentinelCpWeb.NotificationsLive.Helpers do
  @moduledoc """
  Shared components and path helpers for notification LiveViews.
  """
  use Phoenix.Component
  use SentinelCpWeb, :verified_routes

  alias SentinelCp.Orgs

  # -- Shared Components --

  attr :status, :string, required: true

  def status_badge(assigns) do
    color =
      case assigns.status do
        "delivered" -> "badge-success"
        "failed" -> "badge-error"
        "dead_letter" -> "badge-warning"
        "pending" -> "badge-info"
        "delivering" -> "badge-info"
        "skipped" -> "badge-ghost"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-xs", @color]}>{@status}</span>
    """
  end

  attr :org, :any, required: true
  attr :project, :any, required: true
  attr :active, :string, required: true

  def notification_tabs(assigns) do
    ~H"""
    <div class="tabs tabs-bordered">
      <.link
        navigate={notifications_path(@org, @project)}
        class={["tab", @active == "overview" && "tab-active"]}
      >
        Overview
      </.link>
      <.link
        navigate={channels_path(@org, @project)}
        class={["tab", @active == "channels" && "tab-active"]}
      >
        Channels
      </.link>
      <.link
        navigate={rules_path(@org, @project)}
        class={["tab", @active == "rules" && "tab-active"]}
      >
        Rules
      </.link>
      <.link
        navigate={delivery_path(@org, @project)}
        class={["tab", @active == "delivery" && "tab-active"]}
      >
        Delivery
      </.link>
    </div>
    """
  end

  # -- resolve_org --

  def resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  def resolve_org(_), do: nil

  # -- build_config --

  def build_config("slack", params), do: %{"webhook_url" => params["webhook_url"] || ""}
  def build_config("pagerduty", params), do: %{"routing_key" => params["routing_key"] || ""}

  def build_config("email", params) do
    config = %{"to" => params["to"] || ""}

    if params["from"] && params["from"] != "",
      do: Map.put(config, "from", params["from"]),
      else: config
  end

  def build_config("teams", params), do: %{"webhook_url" => params["webhook_url"] || ""}
  def build_config("webhook", params), do: %{"url" => params["url"] || ""}
  def build_config(_, _), do: %{}

  # -- Path Helpers --

  def notifications_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications"

  def notifications_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications"

  def channels_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels"

  def channels_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/channels"

  def rules_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules"

  def rules_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/rules"

  def delivery_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/delivery"

  def delivery_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/delivery"

  def new_channel_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/new"

  def new_channel_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/channels/new"

  def new_rule_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules/new"

  def new_rule_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/rules/new"

  def channel_show_path(%{slug: org_slug}, project, channel),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/#{channel.id}"

  def channel_show_path(nil, project, channel),
    do: ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}"

  def channel_edit_path(%{slug: org_slug}, project, channel),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/#{channel.id}/edit"

  def channel_edit_path(nil, project, channel),
    do: ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}/edit"

  def rule_show_path(%{slug: org_slug}, project, rule),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules/#{rule.id}"

  def rule_show_path(nil, project, rule),
    do: ~p"/projects/#{project.slug}/notifications/rules/#{rule.id}"

  def rule_edit_path(%{slug: org_slug}, project, rule),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules/#{rule.id}/edit"

  def rule_edit_path(nil, project, rule),
    do: ~p"/projects/#{project.slug}/notifications/rules/#{rule.id}/edit"

  def attempt_path(%{slug: org_slug}, project, attempt),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/delivery/#{attempt.id}"

  def attempt_path(nil, project, attempt),
    do: ~p"/projects/#{project.slug}/notifications/delivery/#{attempt.id}"
end
