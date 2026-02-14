defmodule SentinelCpWeb.NotificationsLive.ChannelEdit do
  use SentinelCpWeb, :live_view

  import SentinelCpWeb.NotificationsLive.Helpers

  alias SentinelCp.{Audit, Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         channel when not is_nil(channel) <- Events.get_channel(id),
         true <- channel.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Channel #{channel.name} — #{project.name}",
         org: org,
         project: project,
         channel: channel,
         selected_type: channel.type
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("update_channel", params, socket) do
    channel = socket.assigns.channel
    project = socket.assigns.project

    config = build_config(channel.type, params)

    attrs = %{
      name: params["name"],
      config: config,
      enabled: params["enabled"] == "true"
    }

    case Events.update_channel(channel, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "update",
          "notification_channel",
          updated.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Channel updated.")
         |> push_navigate(to: channel_show_path(socket.assigns.org, project, updated))}

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
      <h1 class="text-xl font-bold">Edit Channel: {@channel.name}</h1>

      <.k8s_section>
        <form phx-submit="update_channel" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@channel.name}
              required
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Type</span></label>
            <span class="badge badge-sm badge-outline">{@channel.type}</span>
            <p class="text-xs text-base-content/50 mt-1">Type cannot be changed after creation.</p>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="enabled"
                value="true"
                checked={@channel.enabled}
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
                value={@channel.config["webhook_url"]}
                required
                class="input input-bordered input-sm w-full font-mono"
              />
            </div>

            <div :if={@selected_type == "pagerduty"} class="form-control">
              <label class="label"><span class="label-text">Routing Key</span></label>
              <input
                type="text"
                name="routing_key"
                value={@channel.config["routing_key"]}
                required
                class="input input-bordered input-sm w-full font-mono"
              />
            </div>

            <div :if={@selected_type == "email"} class="space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text">To</span></label>
                <input
                  type="email"
                  name="to"
                  value={@channel.config["to"]}
                  required
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">From (optional)</span></label>
                <input
                  type="email"
                  name="from"
                  value={@channel.config["from"]}
                  class="input input-bordered input-sm w-full"
                />
              </div>
            </div>

            <div :if={@selected_type == "teams"} class="form-control">
              <label class="label"><span class="label-text">Webhook URL</span></label>
              <input
                type="url"
                name="webhook_url"
                value={@channel.config["webhook_url"]}
                required
                class="input input-bordered input-sm w-full font-mono"
              />
            </div>

            <div :if={@selected_type == "webhook"} class="form-control">
              <label class="label"><span class="label-text">URL</span></label>
              <input
                type="url"
                name="url"
                value={@channel.config["url"]}
                required
                class="input input-bordered input-sm w-full font-mono"
              />
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={channel_show_path(@org, @project, @channel)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end
end
