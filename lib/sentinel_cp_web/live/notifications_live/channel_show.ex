defmodule SentinelCpWeb.NotificationsLive.ChannelShow do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Events, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         channel when not is_nil(channel) <- Events.get_channel(id),
         true <- channel.project_id == project.id do
      attempts = Events.list_delivery_attempts(channel_id: id, limit: 20)

      {:ok,
       assign(socket,
         page_title: "Channel #{channel.name} — #{project.name}",
         org: org,
         project: project,
         channel: channel,
         attempts: attempts
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    channel = socket.assigns.channel
    project = socket.assigns.project
    org = socket.assigns.org

    case Events.delete_channel(channel) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "delete",
          "notification_channel",
          channel.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Channel deleted.")
         |> push_navigate(to: channels_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete channel.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@channel.name}
        resource_type="notification channel"
        back_path={channels_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@channel.enabled && "badge-success") || "badge-ghost"]}>
            {if @channel.enabled, do: "enabled", else: "disabled"}
          </span>
          <span class="badge badge-sm badge-outline">{@channel.type}</span>
        </:badge>
        <:action>
          <.link navigate={edit_path(@org, @project, @channel)} class="btn btn-outline btn-sm">
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this channel?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@channel.id}</span></:item>
            <:item label="Name">{@channel.name}</:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@channel.type}</span>
            </:item>
            <:item label="Enabled">{if @channel.enabled, do: "Yes", else: "No"}</:item>
            <:item label="Signing Secret">
              <span class="font-mono text-sm">
                {String.slice(@channel.signing_secret || "", 0, 8)}••••••••
              </span>
            </:item>
            <:item label="Created">
              {Calendar.strftime(@channel.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Configuration">
          <.definition_list>
            <:item :for={{key, value} <- Enum.sort(@channel.config || %{})} label={key}>
              <span class="font-mono text-sm">{value}</span>
            </:item>
          </.definition_list>
          <div
            :if={@channel.config == nil || @channel.config == %{}}
            class="text-center py-4 text-base-content/50 text-sm"
          >
            No configuration set.
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Recent Deliveries">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Status</th>
              <th class="text-xs">Attempt</th>
              <th class="text-xs">HTTP Status</th>
              <th class="text-xs">Latency</th>
              <th class="text-xs">Time</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @attempts}>
              <td><.status_badge status={a.status} /></td>
              <td>{a.attempt_number}</td>
              <td>{a.http_status || "—"}</td>
              <td>{if a.latency_ms, do: "#{a.latency_ms}ms", else: "—"}</td>
              <td class="text-sm">
                {Calendar.strftime(a.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@attempts == []} class="text-center py-4 text-base-content/50 text-sm">
          No delivery attempts yet.
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

  defp channels_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels"

  defp channels_path(nil, project),
    do: ~p"/projects/#{project.slug}/notifications/channels"

  defp edit_path(%{slug: org_slug}, project, channel),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/notifications/channels/#{channel.id}/edit"

  defp edit_path(nil, project, channel),
    do: ~p"/projects/#{project.slug}/notifications/channels/#{channel.id}/edit"
end
