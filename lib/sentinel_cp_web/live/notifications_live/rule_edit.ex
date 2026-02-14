defmodule SentinelCpWeb.NotificationsLive.RuleEdit do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Events, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         rule when not is_nil(rule) <- Events.get_rule(id),
         rule <- SentinelCp.Repo.preload(rule, :channel),
         true <- rule.project_id == project.id do
      channels = Events.list_channels(project.id)

      {:ok,
       assign(socket,
         page_title: "Edit Rule #{rule.name} — #{project.name}",
         org: org,
         project: project,
         rule: rule,
         channels: channels,
         event_pattern: rule.event_pattern
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("set_pattern", %{"pattern" => pattern}, socket) do
    {:noreply, assign(socket, event_pattern: pattern)}
  end

  @impl true
  def handle_event("update_rule", params, socket) do
    rule = socket.assigns.rule
    project = socket.assigns.project

    attrs = %{
      name: params["name"],
      event_pattern: params["event_pattern"],
      channel_id: params["channel_id"],
      enabled: params["enabled"] == "true"
    }

    case Events.update_rule(rule, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "update",
          "notification_rule",
          updated.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Rule updated.")
         |> push_navigate(to: show_path(socket.assigns.org, project, updated))}

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
      <h1 class="text-xl font-bold">Edit Rule: {@rule.name}</h1>

      <.k8s_section>
        <form phx-submit="update_rule" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@rule.name}
              required
              class="input input-bordered input-sm w-full"
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
              <option :for={ch <- @channels} value={ch.id} selected={ch.id == @rule.channel_id}>
                {ch.name} ({ch.type})
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="enabled"
                value="true"
                checked={@rule.enabled}
                class="checkbox checkbox-sm"
              />
              <span class="label-text font-medium">Enabled</span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={show_path(@org, @project, @rule)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp show_path(%{slug: org_slug}, project, rule),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/rules/#{rule.id}"

  defp show_path(nil, project, rule),
    do: ~p"/projects/#{project.slug}/notifications/rules/#{rule.id}"
end
