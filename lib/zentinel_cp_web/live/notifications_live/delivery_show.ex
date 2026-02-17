defmodule ZentinelCpWeb.NotificationsLive.DeliveryShow do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.NotificationsLive.Helpers

  alias ZentinelCp.{Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         attempt when not is_nil(attempt) <- Events.get_delivery_attempt(id),
         attempt <- ZentinelCp.Repo.preload(attempt, [:event, :channel]),
         true <- attempt.channel.project_id == project.id do
      chain = Events.list_attempt_chain(attempt.event_id, attempt.channel_id)

      {:ok,
       assign(socket,
         page_title: "Delivery Attempt — #{project.name}",
         org: org,
         project: project,
         attempt: attempt,
         chain: chain
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"Delivery Attempt ##{@attempt.attempt_number}"}
        resource_type="delivery attempt"
        back_path={delivery_path(@org, @project)}
      >
        <:badge>
          <.status_badge status={@attempt.status} />
        </:badge>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Summary">
          <.definition_list>
            <:item label="Status"><.status_badge status={@attempt.status} /></:item>
            <:item label="Attempt">{@attempt.attempt_number}</:item>
            <:item label="HTTP Status">{@attempt.http_status || "—"}</:item>
            <:item label="Latency">
              {if @attempt.latency_ms, do: "#{@attempt.latency_ms}ms", else: "—"}
            </:item>
            <:item label="Error">
              <span :if={@attempt.error} class="text-error text-sm">{@attempt.error}</span>
              <span :if={!@attempt.error}>—</span>
            </:item>
            <:item label="Completed At">
              {if @attempt.completed_at,
                do: Calendar.strftime(@attempt.completed_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Created At">
              {Calendar.strftime(@attempt.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Event">
          <.definition_list>
            <:item label="Type">
              <span class="font-mono text-sm">{@attempt.event.type}</span>
            </:item>
            <:item label="Payload">
              <pre class="text-xs bg-base-200 rounded p-2 max-h-48 overflow-auto whitespace-pre-wrap"><%= format_json(@attempt.event.payload) %></pre>
            </:item>
          </.definition_list>
        </.k8s_section>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Channel">
          <.definition_list>
            <:item label="Name">
              <.link navigate={channel_show_path(@org, @project, @attempt.channel)} class="link">
                {@attempt.channel.name}
              </.link>
            </:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@attempt.channel.type}</span>
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Request Body">
          <pre
            :if={@attempt.request_body}
            class="text-xs bg-base-200 rounded p-2 max-h-64 overflow-auto whitespace-pre-wrap"
          ><%= @attempt.request_body %></pre>
          <div :if={!@attempt.request_body} class="text-center py-4 text-base-content/50 text-sm">
            Not captured
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Response Body">
        <pre
          :if={@attempt.response_body}
          class="text-xs bg-base-200 rounded p-2 max-h-64 overflow-auto whitespace-pre-wrap"
        ><%= @attempt.response_body %></pre>
        <div :if={!@attempt.response_body} class="text-center py-4 text-base-content/50 text-sm">
          Not captured
        </div>
      </.k8s_section>

      <.k8s_section title="Attempt Chain">
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Attempt</th>
              <th class="text-xs">Status</th>
              <th class="text-xs">HTTP Status</th>
              <th class="text-xs">Latency</th>
              <th class="text-xs">Error</th>
              <th class="text-xs">Time</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @chain} class={a.id == @attempt.id && "bg-base-200"}>
              <td>
                <.link navigate={attempt_path(@org, @project, a)} class="link">
                  {a.attempt_number}
                </.link>
              </td>
              <td><.status_badge status={a.status} /></td>
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
            </tr>
          </tbody>
        </table>

        <div :if={@chain == []} class="text-center py-4 text-base-content/50 text-sm">
          No attempts found.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp format_json(payload) when is_map(payload), do: Jason.encode!(payload, pretty: true)
  defp format_json(_), do: "—"
end
