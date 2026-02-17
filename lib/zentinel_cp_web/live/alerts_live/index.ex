defmodule ZentinelCpWeb.AlertsLive.Index do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Observability, Projects}

  @refresh_interval 15_000

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket), do: :timer.send_interval(@refresh_interval, :refresh)
        alerts = Observability.list_firing_alerts(project.id)

        {:ok,
         assign(socket,
           page_title: "Active Alerts - #{project.name}",
           org: org,
           project: project,
           alerts: alerts
         )}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    alerts = Observability.list_firing_alerts(socket.assigns.project.id)
    {:noreply, assign(socket, :alerts, alerts)}
  end

  @impl true
  def handle_event("acknowledge", %{"id" => id}, socket) do
    alert_state = Observability.get_alert_state!(id)
    user_id = socket.assigns.current_user.id
    {:ok, _} = Observability.acknowledge_alert(alert_state, user_id)
    alerts = Observability.list_firing_alerts(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:alerts, alerts)
     |> put_flash(:info, "Alert acknowledged.")}
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

      <.alert_tabs org={@org} project={@project} active="active" />

      <div :if={@alerts == []} class="text-center py-12 text-base-content/50">
        <.icon name="hero-check-circle" class="size-12 mx-auto mb-2 opacity-50" />
        <p>No active alerts. All systems normal.</p>
      </div>

      <table :if={@alerts != []} class="table table-sm">
        <thead>
          <tr>
            <th class="text-xs">State</th>
            <th class="text-xs">Rule</th>
            <th class="text-xs">Severity</th>
            <th class="text-xs">Value</th>
            <th class="text-xs">Since</th>
            <th class="text-xs">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={alert <- @alerts}>
            <td><.alert_state_badge state={alert.state} /></td>
            <td>
              <.link
                navigate={alert_rule_path(@org, @project, alert.alert_rule)}
                class="link font-medium"
              >
                {alert.alert_rule.name}
              </.link>
            </td>
            <td><.severity_badge severity={alert.alert_rule.severity} /></td>
            <td class="font-mono text-sm">{format_value(alert.value)}</td>
            <td class="text-sm">
              {if alert.started_at,
                do: Calendar.strftime(alert.started_at, "%Y-%m-%d %H:%M:%S"),
                else: "—"}
            </td>
            <td>
              <button
                :if={is_nil(alert.acknowledged_by)}
                phx-click="acknowledge"
                phx-value-id={alert.id}
                class="btn btn-outline btn-xs"
              >
                Acknowledge
              </button>
              <span :if={alert.acknowledged_by} class="text-xs text-success">Acknowledged</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp format_value(nil), do: "—"
  defp format_value(val) when is_float(val), do: Float.round(val, 2) |> to_string()
  defp format_value(val), do: to_string(val)
end
