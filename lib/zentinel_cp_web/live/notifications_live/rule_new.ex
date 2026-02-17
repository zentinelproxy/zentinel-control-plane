defmodule ZentinelCpWeb.NotificationsLive.RuleNew do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.NotificationsLive.Helpers

  alias ZentinelCp.{Audit, Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        channels = Events.list_channels(project.id)

        {:ok,
         assign(socket,
           page_title: "New Rule — #{project.name}",
           org: org,
           project: project,
           channels: channels,
           event_pattern: ""
         )}
    end
  end

  @impl true
  def handle_event("set_pattern", %{"pattern" => pattern}, socket) do
    {:noreply, assign(socket, event_pattern: pattern)}
  end

  @impl true
  def handle_event("create_rule", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      event_pattern: params["event_pattern"],
      channel_id: params["channel_id"],
      enabled: params["enabled"] == "true"
    }

    case Events.create_rule(attrs) do
      {:ok, rule} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "create",
          "notification_rule",
          rule.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Rule created.")
         |> push_navigate(to: rule_show_path(socket.assigns.org, project, rule))}

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
      <h1 class="text-xl font-bold">Create Notification Rule</h1>

      <.k8s_section>
        <form phx-submit="create_rule" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. Rollout Failures to Slack"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Event Pattern</span></label>
            <input
              type="text"
              name="event_pattern"
              value={@event_pattern}
              required
              class="input input-bordered input-sm w-full font-mono"
              placeholder="e.g. rollout.* or bundle.created"
            />
            <div class="flex gap-1 mt-2 flex-wrap">
              <button
                :for={p <- ["rollout.*", "bundle.*", "drift.*", "node.*", "*"]}
                type="button"
                phx-click="set_pattern"
                phx-value-pattern={p}
                class="btn btn-xs btn-outline font-mono"
              >
                {p}
              </button>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Channel</span></label>
            <select name="channel_id" required class="select select-bordered select-sm w-full">
              <option value="">Select a channel...</option>
              <option :for={ch <- @channels} value={ch.id}>
                {ch.name} ({ch.type})
              </option>
            </select>
            <div :if={@channels == []} class="text-xs text-warning mt-1">
              No channels available.
              <.link navigate={new_channel_path(@org, @project)} class="link">
                Create a channel first.
              </.link>
            </div>
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

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm" disabled={@channels == []}>
              Create Rule
            </button>
            <.link navigate={rules_path(@org, @project)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end
end
