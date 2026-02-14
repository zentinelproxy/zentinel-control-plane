defmodule SentinelCpWeb.NotificationsLive.Channels do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Events, Orgs, Projects}

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
           page_title: "Notification Channels — #{project.name}",
           org: org,
           project: project,
           channels: channels
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project
    channel = Events.get_channel!(id)

    case Events.delete_channel(channel) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "delete",
          "notification_channel",
          channel.id,
          project_id: project.id
        )

        channels = Events.list_channels(project.id)
        {:noreply, assign(socket, channels: channels) |> put_flash(:info, "Channel deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete channel.")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = socket.assigns.project
    channel = Events.get_channel!(id)

    case Events.update_channel(channel, %{enabled: !channel.enabled}) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "update",
          "notification_channel",
          channel.id,
          project_id: project.id
        )

        channels = Events.list_channels(project.id)
        {:noreply, assign(socket, channels: channels)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update channel.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Notification Channels</h1>
        <.link navigate={new_channel_path(@org, @project)} class="btn btn-primary btn-sm">
          New Channel
        </.link>
      </div>

      <.notification_tabs org={@org} project={@project} active="channels" />

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Type</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs">Created</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ch <- @channels}>
              <td>
                <.link navigate={show_channel_path(@org, @project, ch)} class="link link-primary">
                  {ch.name}
                </.link>
              </td>
              <td><span class="badge badge-sm badge-outline">{ch.type}</span></td>
              <td>
                <button phx-click="toggle_enabled" phx-value-id={ch.id} class="cursor-pointer">
                  <span class={[
                    "badge badge-xs",
                    (ch.enabled && "badge-success") || "badge-ghost"
                  ]}>
                    {if ch.enabled, do: "yes", else: "no"}
                  </span>
                </button>
              </td>
              <td class="text-sm">{Calendar.strftime(ch.inserted_at, "%Y-%m-%d")}</td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={ch.id}
                  data-confirm="Are you sure you want to delete this channel?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@channels == []} class="text-center py-8 text-base-content/50 text-sm">
          No notification channels yet. Create one to start receiving alerts.
        </div>
      </.k8s_section>
    </div>
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

  defp new_channel_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/new"

  defp new_channel_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/channels/new"

  defp show_channel_path(%{slug: org_slug}, project, channel),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/#{channel.id}"

  defp show_channel_path(nil, project, channel),
    do: ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}"
end
