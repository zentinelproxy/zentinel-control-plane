defmodule ZentinelCpWeb.AlertsLive.Rules do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Observability, Projects}
  alias ZentinelCp.Observability.AlertRule

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        rules = Observability.list_alert_rules(project.id)

        {:ok,
         assign(socket,
           page_title: "Alert Rules - #{project.name}",
           org: org,
           project: project,
           rules: rules
         )}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    rule = Observability.get_alert_rule!(id)
    {:ok, _} = Observability.update_alert_rule(rule, %{enabled: !rule.enabled})
    rules = Observability.list_alert_rules(socket.assigns.project.id)

    {:noreply, assign(socket, :rules, rules)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = Observability.get_alert_rule!(id)
    {:ok, _} = Observability.delete_alert_rule(rule)
    rules = Observability.list_alert_rules(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:rules, rules)
     |> put_flash(:info, "Alert rule deleted.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Alerts</h1>
        <.link navigate={new_alert_rule_path(@org, @project)} class="btn btn-primary btn-sm">
          New Rule
        </.link>
      </div>

      <.alert_tabs org={@org} project={@project} active="rules" />

      <div :if={@rules == []} class="text-center py-12 text-base-content/50">
        <p>No alert rules defined yet.</p>
        <.link navigate={new_alert_rule_path(@org, @project)} class="btn btn-outline btn-sm mt-4">
          Create your first rule
        </.link>
      </div>

      <table :if={@rules != []} class="table table-sm">
        <thead>
          <tr>
            <th class="text-xs">Name</th>
            <th class="text-xs">Type</th>
            <th class="text-xs">Severity</th>
            <th class="text-xs">Enabled</th>
            <th class="text-xs">Silenced</th>
            <th class="text-xs">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={rule <- @rules}>
            <td>
              <.link navigate={alert_rule_path(@org, @project, rule)} class="link font-medium">
                {rule.name}
              </.link>
            </td>
            <td><span class="badge badge-sm badge-outline">{rule.rule_type}</span></td>
            <td><.severity_badge severity={rule.severity} /></td>
            <td>
              <input
                type="checkbox"
                checked={rule.enabled}
                phx-click="toggle_enabled"
                phx-value-id={rule.id}
                class="toggle toggle-sm toggle-success"
              />
            </td>
            <td>
              {if AlertRule.silenced?(rule), do: "Yes", else: "No"}
            </td>
            <td class="flex gap-1">
              <.link
                navigate={edit_alert_rule_path(@org, @project, rule)}
                class="btn btn-outline btn-xs"
              >
                Edit
              </.link>
              <button
                phx-click="delete"
                phx-value-id={rule.id}
                data-confirm="Delete this alert rule?"
                class="btn btn-error btn-xs"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
