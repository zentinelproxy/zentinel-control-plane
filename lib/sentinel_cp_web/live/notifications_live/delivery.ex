defmodule SentinelCpWeb.NotificationsLive.Delivery do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Events, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        channels = Events.list_channels(project.id)
        attempts = Events.list_delivery_attempts(project_id: project.id, limit: 50)

        {:ok,
         assign(socket,
           page_title: "Delivery Monitor — #{project.name}",
           org: org,
           project: project,
           channels: channels,
           attempts: attempts,
           status_filter: nil,
           channel_filter: nil
         )}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    project = socket.assigns.project

    status_filter =
      case params["status"] do
        "" -> nil
        s -> s
      end

    channel_filter =
      case params["channel_id"] do
        "" -> nil
        c -> c
      end

    opts = [project_id: project.id, limit: 50]
    opts = if status_filter, do: Keyword.put(opts, :status, status_filter), else: opts
    opts = if channel_filter, do: Keyword.put(opts, :channel_id, channel_filter), else: opts

    attempts = Events.list_delivery_attempts(opts)

    {:noreply,
     assign(socket,
       attempts: attempts,
       status_filter: status_filter,
       channel_filter: channel_filter
     )}
  end

  @impl true
  def handle_event("retry", %{"id" => id}, socket) do
    case Events.retry_delivery(id) do
      {:ok, _} ->
        project = socket.assigns.project
        attempts = Events.list_delivery_attempts(project_id: project.id, limit: 50)

        {:noreply,
         assign(socket, attempts: attempts)
         |> put_flash(:info, "Delivery retry scheduled.")}

      {:error, :not_in_dead_letter} ->
        {:noreply, put_flash(socket, :error, "Only dead-letter deliveries can be retried.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Delivery Monitor</h1>
      </div>

      <.notification_tabs org={@org} project={@project} active="delivery" />

      <div class="flex gap-4 items-end">
        <form phx-change="filter" class="flex gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Status</span></label>
            <select name="status" class="select select-bordered select-sm w-40">
              <option value="">All</option>
              <option
                :for={s <- ~w(pending delivering delivered failed dead_letter)}
                value={s}
                selected={s == @status_filter}
              >
                {s}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Channel</span></label>
            <select name="channel_id" class="select select-bordered select-sm w-48">
              <option value="">All</option>
              <option :for={ch <- @channels} value={ch.id} selected={ch.id == @channel_filter}>
                {ch.name}
              </option>
            </select>
          </div>
        </form>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Event Type</th>
              <th class="text-xs">Channel</th>
              <th class="text-xs">Status</th>
              <th class="text-xs">Attempt</th>
              <th class="text-xs">HTTP Status</th>
              <th class="text-xs">Latency</th>
              <th class="text-xs">Error</th>
              <th class="text-xs">Time</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @attempts}>
              <td>
                <.link
                  navigate={attempt_path(@org, @project, a)}
                  class="font-mono text-sm link"
                >
                  {(a.event && a.event.type) || "—"}
                </.link>
              </td>
              <td>
                <span class="text-sm">{(a.channel && a.channel.name) || "—"}</span>
              </td>
              <td><.status_badge status={a.status} /></td>
              <td>{a.attempt_number}</td>
              <td>{a.http_status || "—"}</td>
              <td>{if a.latency_ms, do: "#{a.latency_ms}ms", else: "—"}</td>
              <td>
                <span :if={a.error} class="text-xs text-error" title={a.error}>
                  {String.slice(a.error, 0, 40)}{if String.length(a.error || "") > 40,
                    do: "...",
                    else: ""}
                </span>
                <span :if={!a.error}>—</span>
              </td>
              <td class="text-sm">
                {Calendar.strftime(a.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td>
                <button
                  :if={a.status == "dead_letter"}
                  phx-click="retry"
                  phx-value-id={a.id}
                  class="btn btn-ghost btn-xs"
                >
                  Retry
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@attempts == []} class="text-center py-8 text-base-content/50 text-sm">
          No delivery attempts found.
        </div>
      </.k8s_section>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    color =
      case assigns.status do
        "delivered" -> "badge-success"
        "failed" -> "badge-error"
        "dead_letter" -> "badge-warning"
        "pending" -> "badge-info"
        "delivering" -> "badge-info"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-xs", @color]}>{@status}</span>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  attr :org, :any, required: true
  attr :project, :any, required: true
  attr :active, :string, required: true

  defp notification_tabs(assigns) do
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

  defp notifications_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications"

  defp notifications_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications"

  defp channels_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels"

  defp channels_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/channels"

  defp rules_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules"

  defp rules_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/rules"

  defp delivery_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/delivery"

  defp delivery_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/delivery"

  defp attempt_path(%{slug: org_slug}, project, attempt),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/delivery/#{attempt.id}"

  defp attempt_path(nil, project, attempt),
    do: ~p"/projects/#{project.slug}/notifications/delivery/#{attempt.id}"
end
