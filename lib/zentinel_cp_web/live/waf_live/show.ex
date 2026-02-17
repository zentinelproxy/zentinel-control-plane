defmodule ZentinelCpWeb.WafLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Analytics, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        case Analytics.get_waf_event(id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "WAF event not found.")
             |> push_navigate(to: waf_index_path(org, project))}

          event ->
            {:ok,
             assign(socket,
               page_title: "WAF Event — #{event.rule_type}",
               org: org,
               project: project,
               event: event
             )}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"WAF Event — #{@event.rule_type}"}
        resource_type="node"
        back_path={waf_index_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", severity_class(@event.severity)]}>
            {@event.severity || "unknown"}
          </span>
          <span class={["badge badge-sm", action_class(@event.action)]}>
            {@event.action}
          </span>
        </:badge>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Event Info" testid="waf-event-info">
          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-base-content/70">Timestamp</dt>
              <dd>{format_datetime(@event.timestamp)}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/70">Rule Type</dt>
              <dd><span class="badge badge-xs badge-outline">{@event.rule_type}</span></dd>
            </div>
            <div :if={@event.rule_id} class="flex justify-between">
              <dt class="text-base-content/70">Rule ID</dt>
              <dd class="font-mono text-xs">{@event.rule_id}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-base-content/70">Action</dt>
              <dd>
                <span class={["badge badge-xs", action_class(@event.action)]}>
                  {@event.action}
                </span>
              </dd>
            </div>
            <div :if={@event.severity} class="flex justify-between">
              <dt class="text-base-content/70">Severity</dt>
              <dd>
                <span class={["badge badge-xs", severity_class(@event.severity)]}>
                  {@event.severity}
                </span>
              </dd>
            </div>
            <div :if={@event.client_ip} class="flex justify-between">
              <dt class="text-base-content/70">Client IP</dt>
              <dd class="font-mono text-xs">{@event.client_ip}</dd>
            </div>
            <div :if={@event.method} class="flex justify-between">
              <dt class="text-base-content/70">Method</dt>
              <dd>{@event.method}</dd>
            </div>
            <div :if={@event.path} class="flex justify-between">
              <dt class="text-base-content/70">Path</dt>
              <dd class="font-mono text-xs break-all max-w-xs text-right">{@event.path}</dd>
            </div>
            <div :if={@event.matched_data} class="flex justify-between">
              <dt class="text-base-content/70">Matched Data</dt>
              <dd class="font-mono text-xs break-all max-w-xs text-right">{@event.matched_data}</dd>
            </div>
            <div :if={@event.user_agent} class="flex justify-between">
              <dt class="text-base-content/70">User Agent</dt>
              <dd class="text-xs break-all max-w-xs text-right">{@event.user_agent}</dd>
            </div>
            <div :if={@event.geo_country} class="flex justify-between">
              <dt class="text-base-content/70">Country</dt>
              <dd>{@event.geo_country}</dd>
            </div>
          </dl>
        </.k8s_section>

        <div class="space-y-4">
          <.k8s_section title="Request Headers" testid="waf-event-headers">
            <div
              :if={@event.request_headers == %{}}
              class="text-base-content/50 text-sm py-2 text-center"
            >
              No headers recorded.
            </div>
            <dl :if={@event.request_headers != %{}} class="space-y-2 text-sm">
              <div
                :for={{key, value} <- Enum.sort(@event.request_headers)}
                class="flex justify-between gap-4"
              >
                <dt class="text-base-content/70 font-mono text-xs shrink-0">{key}</dt>
                <dd class="font-mono text-xs break-all text-right">{value}</dd>
              </div>
            </dl>
          </.k8s_section>

          <.k8s_section title="Metadata" testid="waf-event-metadata">
            <div :if={@event.metadata == %{}} class="text-base-content/50 text-sm py-2 text-center">
              No metadata.
            </div>
            <dl :if={@event.metadata != %{}} class="space-y-2 text-sm">
              <div
                :for={{key, value} <- Enum.sort(@event.metadata)}
                class="flex justify-between gap-4"
              >
                <dt class="text-base-content/70 font-mono text-xs shrink-0">{key}</dt>
                <dd class="font-mono text-xs break-all text-right">{inspect(value)}</dd>
              </div>
            </dl>
          </.k8s_section>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp waf_index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf"

  defp waf_index_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf"

  defp action_class("blocked"), do: "badge-error"
  defp action_class("challenged"), do: "badge-warning"
  defp action_class(_), do: "badge-info"

  defp severity_class("critical"), do: "badge-error"
  defp severity_class("high"), do: "badge-error"
  defp severity_class("medium"), do: "badge-warning"
  defp severity_class("low"), do: "badge-info"
  defp severity_class(_), do: "badge-ghost"

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
