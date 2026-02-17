defmodule ZentinelCpWeb.AlertsLive.RuleShow do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Audit, Observability, Projects}
  alias ZentinelCp.Observability.AlertRule

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         rule when not is_nil(rule) <- Observability.get_alert_rule(id),
         true <- rule.project_id == project.id do
      states = Observability.list_recent_alert_states(rule.id, limit: 50)

      {:ok,
       assign(socket,
         page_title: "#{rule.name} - #{project.name}",
         org: org,
         project: project,
         rule: rule,
         states: states
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("silence", %{"hours" => hours_str}, socket) do
    rule = socket.assigns.rule

    hours =
      case Integer.parse(hours_str) do
        {h, _} -> h
        :error -> 1
      end

    until =
      DateTime.utc_now() |> DateTime.add(hours * 3600, :second) |> DateTime.truncate(:second)

    {:ok, updated} = Observability.silence_alert_rule(rule, until)

    Audit.log_user_action(
      socket.assigns.current_user,
      "silence",
      "alert_rule",
      rule.id,
      project_id: socket.assigns.project.id
    )

    {:noreply,
     socket
     |> assign(:rule, updated)
     |> put_flash(:info, "Rule silenced for #{hours} hour(s).")}
  end

  @impl true
  def handle_event("unsilence", _, socket) do
    rule = socket.assigns.rule
    {:ok, updated} = Observability.unsilence_alert_rule(rule)

    {:noreply,
     socket
     |> assign(:rule, updated)
     |> put_flash(:info, "Rule unsilenced.")}
  end

  @impl true
  def handle_event("delete", _, socket) do
    rule = socket.assigns.rule
    project = socket.assigns.project

    {:ok, _} = Observability.delete_alert_rule(rule)

    Audit.log_user_action(
      socket.assigns.current_user,
      "delete",
      "alert_rule",
      rule.id,
      project_id: project.id
    )

    {:noreply,
     socket
     |> put_flash(:info, "Alert rule deleted.")
     |> push_navigate(to: alert_rules_path(socket.assigns.org, project))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@rule.name}
        resource_type="alert rule"
        back_path={alert_rules_path(@org, @project)}
      >
        <:badge>
          <.severity_badge severity={@rule.severity} />
          <span class="badge badge-sm badge-outline">{@rule.rule_type}</span>
          <span class={["badge badge-sm", (@rule.enabled && "badge-success") || "badge-ghost"]}>
            {if @rule.enabled, do: "enabled", else: "disabled"}
          </span>
          <span :if={AlertRule.silenced?(@rule)} class="badge badge-sm badge-warning">silenced</span>
        </:badge>
        <:action>
          <.link navigate={edit_alert_rule_path(@org, @project, @rule)} class="btn btn-outline btn-sm">
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this alert rule?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="Name">{@rule.name}</:item>
            <:item label="Description">{@rule.description || "—"}</:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@rule.rule_type}</span>
            </:item>
            <:item label="Severity"><.severity_badge severity={@rule.severity} /></:item>
            <:item label="Grace Period">{@rule.for_seconds}s</:item>
            <:item label="Condition">
              <code class="text-xs">{format_condition(@rule.condition)}</code>
            </:item>
            <:item label="Created">
              {Calendar.strftime(@rule.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Silence Controls">
          <div :if={AlertRule.silenced?(@rule)} class="space-y-2">
            <p class="text-sm text-warning">
              Silenced until {Calendar.strftime(@rule.silenced_until, "%Y-%m-%d %H:%M:%S UTC")}
            </p>
            <button phx-click="unsilence" class="btn btn-outline btn-sm">Unsilence</button>
          </div>

          <div :if={!AlertRule.silenced?(@rule)} class="space-y-2">
            <p class="text-sm text-base-content/50">Silence this rule to suppress notifications.</p>
            <div class="flex gap-2">
              <button phx-click="silence" phx-value-hours="1" class="btn btn-outline btn-xs">
                1h
              </button>
              <button phx-click="silence" phx-value-hours="4" class="btn btn-outline btn-xs">
                4h
              </button>
              <button phx-click="silence" phx-value-hours="24" class="btn btn-outline btn-xs">
                24h
              </button>
            </div>
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Alert History">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">State</th>
              <th class="text-xs">Value</th>
              <th class="text-xs">Started</th>
              <th class="text-xs">Firing At</th>
              <th class="text-xs">Resolved At</th>
              <th class="text-xs">Acknowledged</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={state <- @states}>
              <td><.alert_state_badge state={state.state} /></td>
              <td class="font-mono text-sm">{format_value(state.value)}</td>
              <td class="text-sm">
                {if state.started_at,
                  do: Calendar.strftime(state.started_at, "%m-%d %H:%M:%S"),
                  else: "—"}
              </td>
              <td class="text-sm">
                {if state.firing_at,
                  do: Calendar.strftime(state.firing_at, "%m-%d %H:%M:%S"),
                  else: "—"}
              </td>
              <td class="text-sm">
                {if state.resolved_at,
                  do: Calendar.strftime(state.resolved_at, "%m-%d %H:%M:%S"),
                  else: "—"}
              </td>
              <td class="text-sm">
                {if state.acknowledged_by, do: "Yes", else: "—"}
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@states == []} class="text-center py-4 text-base-content/50 text-sm">
          No alert history yet.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp format_condition(%{"metric" => metric, "operator" => op, "value" => val}) do
    "#{metric} #{op} #{val}"
  end

  defp format_condition(%{"slo_id" => slo_id, "burn_rate_threshold" => threshold}) do
    "SLO #{String.slice(slo_id || "", 0, 8)}... burn rate > #{threshold}"
  end

  defp format_condition(condition), do: inspect(condition)

  defp format_value(nil), do: "—"
  defp format_value(val) when is_float(val), do: Float.round(val, 2) |> to_string()
  defp format_value(val), do: to_string(val)
end
