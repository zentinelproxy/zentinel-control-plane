defmodule ZentinelCpWeb.NotificationsLive.Index do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.NotificationsLive.Helpers

  alias ZentinelCp.{Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        stats = Events.delivery_stats(project.id)
        recent_events = Events.list_events(project_id: project.id, limit: 20)

        {:ok,
         assign(socket,
           page_title: "Notifications — #{project.name}",
           org: org,
           project: project,
           stats: stats,
           recent_events: recent_events
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Notifications</h1>
      </div>

      <.notification_tabs org={@org} project={@project} active="overview" />

      <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
        <.stat_card label="Total" value={@stats.total} />
        <.stat_card label="Delivered" value={@stats.delivered} color="success" />
        <.stat_card label="Failed" value={@stats.failed} color="error" />
        <.stat_card label="Dead Letter" value={@stats.dead_letter} color="warning" />
        <.stat_card label="Pending" value={@stats.pending} color="info" />
      </div>

      <.k8s_section title="Recent Events (24h)">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Type</th>
              <th class="text-xs">Emitted At</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={event <- @recent_events}>
              <td><span class="font-mono text-sm">{event.type}</span></td>
              <td class="text-sm">
                {Calendar.strftime(event.emitted_at, "%Y-%m-%d %H:%M:%S UTC")}
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@recent_events == []} class="text-center py-8 text-base-content/50 text-sm">
          No events emitted yet.
        </div>
      </.k8s_section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="stat bg-base-200 rounded-lg p-4">
      <div class="stat-title text-xs">{@label}</div>
      <div class={["stat-value text-2xl", @color && "text-#{@color}"]}>{@value}</div>
    </div>
    """
  end
end
