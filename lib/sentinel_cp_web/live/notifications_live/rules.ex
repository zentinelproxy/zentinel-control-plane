defmodule SentinelCpWeb.NotificationsLive.Rules do
  use SentinelCpWeb, :live_view

  import SentinelCpWeb.NotificationsLive.Helpers

  alias SentinelCp.{Audit, Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        rules = Events.list_rules(project.id)

        {:ok,
         assign(socket,
           page_title: "Notification Rules — #{project.name}",
           org: org,
           project: project,
           rules: rules
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project

    with rule when not is_nil(rule) <- Events.get_rule(id),
         true <- rule.project_id == project.id do
      case Events.delete_rule(rule) do
        {:ok, _} ->
          Audit.log_user_action(
            socket.assigns.current_user,
            "delete",
            "notification_rule",
            rule.id,
            project_id: project.id
          )

          rules = Events.list_rules(project.id)
          {:noreply, assign(socket, rules: rules) |> put_flash(:info, "Rule deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete rule.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Rule not found.")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = socket.assigns.project

    with rule when not is_nil(rule) <- Events.get_rule(id),
         true <- rule.project_id == project.id do
      case Events.update_rule(rule, %{enabled: !rule.enabled}) do
        {:ok, _} ->
          Audit.log_user_action(
            socket.assigns.current_user,
            "update",
            "notification_rule",
            rule.id,
            project_id: project.id
          )

          rules = Events.list_rules(project.id)
          {:noreply, assign(socket, rules: rules)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update rule.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Rule not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Notification Rules</h1>
        <.link navigate={new_rule_path(@org, @project)} class="btn btn-primary btn-sm">
          New Rule
        </.link>
      </div>

      <.notification_tabs org={@org} project={@project} active="rules" />

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Event Pattern</th>
              <th class="text-xs">Channel</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rule <- @rules}>
              <td>
                <.link navigate={rule_show_path(@org, @project, rule)} class="link link-primary">
                  {rule.name}
                </.link>
              </td>
              <td><span class="font-mono text-sm">{rule.event_pattern}</span></td>
              <td>
                <.link navigate={channel_show_path(@org, @project, rule.channel)} class="link">
                  {rule.channel.name}
                </.link>
                <span class="badge badge-xs badge-outline ml-1">{rule.channel.type}</span>
              </td>
              <td>
                <button phx-click="toggle_enabled" phx-value-id={rule.id} class="cursor-pointer">
                  <span class={[
                    "badge badge-xs",
                    (rule.enabled && "badge-success") || "badge-ghost"
                  ]}>
                    {if rule.enabled, do: "yes", else: "no"}
                  </span>
                </button>
              </td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={rule.id}
                  data-confirm="Are you sure you want to delete this rule?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@rules == []} class="text-center py-8 text-base-content/50 text-sm">
          No notification rules yet. Create one to route events to channels.
        </div>
      </.k8s_section>
    </div>
    """
  end
end
