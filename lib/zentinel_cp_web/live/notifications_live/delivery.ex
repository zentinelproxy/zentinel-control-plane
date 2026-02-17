defmodule ZentinelCpWeb.NotificationsLive.Delivery do
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
    project = socket.assigns.project
    attempt = Events.get_delivery_attempt(id)

    with attempt when not is_nil(attempt) <- attempt,
         channel when not is_nil(channel) <- Events.get_channel(attempt.channel_id),
         true <- channel.project_id == project.id do
      case Events.retry_delivery(id) do
        {:ok, _} ->
          attempts = Events.list_delivery_attempts(project_id: project.id, limit: 50)

          {:noreply,
           assign(socket, attempts: attempts)
           |> put_flash(:info, "Delivery retry scheduled.")}

        {:error, :not_in_dead_letter} ->
          {:noreply, put_flash(socket, :error, "Only dead-letter deliveries can be retried.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Delivery attempt not found.")}
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
                :for={s <- ~w(pending delivering delivered failed dead_letter skipped)}
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
                <.link
                  :if={a.channel}
                  navigate={channel_show_path(@org, @project, a.channel)}
                  class="text-sm link"
                >
                  {a.channel.name}
                </.link>
                <span :if={!a.channel} class="text-sm">—</span>
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
end
