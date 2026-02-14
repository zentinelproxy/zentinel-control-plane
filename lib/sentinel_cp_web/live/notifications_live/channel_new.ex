defmodule SentinelCpWeb.NotificationsLive.ChannelNew do
  use SentinelCpWeb, :live_view

  import SentinelCpWeb.NotificationsLive.Helpers

  alias SentinelCp.{Audit, Events, Projects}
  alias SentinelCp.Events.Channel

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New Channel — #{project.name}",
           org: org,
           project: project,
           channel_types: Channel.types(),
           selected_type: "slack"
         )}
    end
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_type: type)}
  end

  @impl true
  def handle_event("create_channel", params, socket) do
    project = socket.assigns.project

    config = build_config(socket.assigns.selected_type, params)

    attrs = %{
      project_id: project.id,
      name: params["name"],
      type: params["type"],
      config: config,
      enabled: params["enabled"] == "true"
    }

    case Events.create_channel(attrs) do
      {:ok, channel} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "create",
          "notification_channel",
          channel.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Channel created.")
         |> push_navigate(to: channel_show_path(socket.assigns.org, project, channel))}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">Create Notification Channel</h1>

      <.k8s_section>
        <form phx-submit="create_channel" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. Production Alerts"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Type</span></label>
            <select
              name="type"
              phx-change="select_type"
              phx-value-type=""
              class="select select-bordered select-sm w-48"
            >
              <option :for={t <- @channel_types} value={t} selected={t == @selected_type}>
                {String.capitalize(t)}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="enabled"
                value="true"
                checked
                class="checkbox checkbox-sm"
              />
              <span class="label-text font-medium">Enabled</span>
            </label>
          </div>

          <div class="space-y-4 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Channel Configuration</p>

            <div :if={@selected_type == "slack"} class="form-control">
              <label class="label"><span class="label-text">Webhook URL</span></label>
              <input
                type="url"
                name="webhook_url"
                required
                class="input input-bordered input-sm w-full font-mono"
                placeholder="https://hooks.slack.com/services/..."
              />
            </div>

            <div :if={@selected_type == "pagerduty"} class="form-control">
              <label class="label"><span class="label-text">Routing Key</span></label>
              <input
                type="text"
                name="routing_key"
                required
                class="input input-bordered input-sm w-full font-mono"
                placeholder="PagerDuty routing key"
              />
            </div>

            <div :if={@selected_type == "email"} class="space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text">To</span></label>
                <input
                  type="email"
                  name="to"
                  required
                  class="input input-bordered input-sm w-full"
                  placeholder="alerts@example.com"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">From (optional)</span></label>
                <input
                  type="email"
                  name="from"
                  class="input input-bordered input-sm w-full"
                  placeholder="sentinel@example.com"
                />
              </div>
            </div>

            <div :if={@selected_type == "teams"} class="form-control">
              <label class="label"><span class="label-text">Webhook URL</span></label>
              <input
                type="url"
                name="webhook_url"
                required
                class="input input-bordered input-sm w-full font-mono"
                placeholder="https://outlook.office.com/webhook/..."
              />
            </div>

            <div :if={@selected_type == "webhook"} class="form-control">
              <label class="label"><span class="label-text">URL</span></label>
              <input
                type="url"
                name="url"
                required
                class="input input-bordered input-sm w-full font-mono"
                placeholder="https://example.com/webhook"
              />
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Channel</button>
            <.link navigate={channels_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end
end
