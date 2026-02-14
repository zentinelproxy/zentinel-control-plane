defmodule SentinelCpWeb.ServicesLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}
  alias SentinelCp.Services.KdlGenerator

  @impl true
  def mount(%{"project_slug" => slug, "id" => service_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         service when not is_nil(service) <- Services.get_service(service_id),
         true <- service.project_id == project.id do
      {:ok, config} = Services.get_or_create_project_config(project.id)
      kdl_preview = generate_service_preview(service, config)

      auth_policy =
        if service.auth_policy_id, do: Services.get_auth_policy(service.auth_policy_id), else: nil

      middleware_chain = Services.list_service_middlewares(service.id)
      available_middlewares = Services.list_middlewares(project.id)

      {:ok,
       assign(socket,
         page_title: "Service #{service.name} — #{project.name}",
         org: org,
         project: project,
         service: service,
         auth_policy: auth_policy,
         middleware_chain: middleware_chain,
         available_middlewares: available_middlewares,
         kdl_preview: kdl_preview
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    service = socket.assigns.service
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_service(service) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "service", service.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Service deleted.")
         |> push_navigate(to: project_services_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete service.")}
    end
  end

  @impl true
  def handle_event("attach_middleware", %{"middleware_id" => mw_id}, socket) do
    service = socket.assigns.service
    project = socket.assigns.project
    chain = socket.assigns.middleware_chain
    next_position = if chain == [], do: 0, else: Enum.max_by(chain, & &1.position).position + 1

    case Services.attach_middleware(%{
           service_id: service.id,
           middleware_id: mw_id,
           position: next_position
         }) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "attach",
          "service_middleware",
          service.id,
          project_id: project.id
        )

        middleware_chain = Services.list_service_middlewares(service.id)

        {:noreply,
         assign(socket, middleware_chain: middleware_chain)
         |> put_flash(:info, "Middleware attached.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not attach middleware.")}
    end
  end

  @impl true
  def handle_event("detach_middleware", %{"id" => sm_id}, socket) do
    project = socket.assigns.project
    service = socket.assigns.service

    case Services.get_service_middleware(sm_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Service middleware not found.")}

      sm ->
        case Services.detach_middleware(sm) do
          {:ok, _} ->
            Audit.log_user_action(
              socket.assigns.current_user,
              "detach",
              "service_middleware",
              service.id,
              project_id: project.id
            )

            middleware_chain = Services.list_service_middlewares(service.id)

            {:noreply,
             assign(socket, middleware_chain: middleware_chain)
             |> put_flash(:info, "Middleware detached.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not detach middleware.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@service.name}
        resource_type="service"
        back_path={project_services_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@service.enabled && "badge-success") || "badge-ghost"]}>
            {if @service.enabled, do: "enabled", else: "disabled"}
          </span>
        </:badge>
        <:action>
          <.link
            navigate={service_edit_path(@org, @project, @service)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this service?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Definition">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@service.id}</span></:item>
            <:item label="Name">{@service.name}</:item>
            <:item label="Slug"><span class="font-mono">{@service.slug}</span></:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@service.service_type || "standard"}</span>
            </:item>
            <:item label="Description">{@service.description || "—"}</:item>
            <:item label="Route Path"><span class="font-mono">{@service.route_path}</span></:item>
            <:item label="Upstream">
              <span class="font-mono">{@service.upstream_url || "—"}</span>
            </:item>
            <:item label="Static Response">
              {if @service.respond_status && !@service.redirect_url,
                do: "#{@service.respond_status} #{@service.respond_body}",
                else: "—"}
            </:item>
            <:item label="Redirect">
              {if @service.redirect_url,
                do: "#{@service.respond_status || 301} → #{@service.redirect_url}",
                else: "—"}
            </:item>
            <:item label="Timeout">
              {if @service.timeout_seconds, do: "#{@service.timeout_seconds}s", else: "—"}
            </:item>
            <:item label="Position">{@service.position}</:item>
            <:item label="Created">
              {Calendar.strftime(@service.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Policies">
          <.definition_list>
            <:item label="Retry">{format_map(@service.retry)}</:item>
            <:item label="Cache">{format_map(@service.cache)}</:item>
            <:item label="Rate Limit">{format_map(@service.rate_limit)}</:item>
            <:item label="Health Check">{format_map(@service.health_check)}</:item>
            <:item label="Headers">{format_map(@service.headers)}</:item>
            <:item label="CORS">{format_map(@service.cors)}</:item>
            <:item label="Access Control">{format_map(@service.access_control)}</:item>
            <:item label="Compression">{format_map(@service.compression)}</:item>
            <:item label="Path Rewrite">{format_map(@service.path_rewrite)}</:item>
            <:item label="Auth Policy">
              {if @auth_policy, do: "#{@auth_policy.name} (#{@auth_policy.auth_type})", else: "—"}
            </:item>
            <:item label="Security">{format_map(@service.security)}</:item>
            <:item label="Request Transform">{format_map(@service.request_transform)}</:item>
            <:item label="Response Transform">{format_map(@service.response_transform)}</:item>
            <:item label="Traffic Split">{format_traffic_split(@service.traffic_split)}</:item>
          </.definition_list>
        </.k8s_section>

        <div
          :if={@service.service_type && @service.service_type != "standard"}
          data-testid="protocol-config"
        >
          <.k8s_section title="Protocol Configuration">
            <div :if={@service.service_type == "graphql" and @service.graphql != %{}}>
              <.definition_list>
                <:item label="Max Depth">{@service.graphql["max_depth"] || "—"}</:item>
                <:item label="Max Complexity">{@service.graphql["max_complexity"] || "—"}</:item>
                <:item label="Introspection">{@service.graphql["introspection"] || "—"}</:item>
                <:item label="Persisted Queries">
                  {@service.graphql["persisted_queries"] || "—"}
                </:item>
                <:item label="Playground Path">{@service.graphql["playground_path"] || "—"}</:item>
              </.definition_list>
            </div>
            <div :if={@service.service_type == "grpc" and @service.grpc != %{}}>
              <.definition_list>
                <:item label="Max Message Size">{@service.grpc["max_message_size"] || "—"}</:item>
                <:item label="Reflection">{@service.grpc["reflection"] || "—"}</:item>
                <:item label="Health Check Service">
                  {@service.grpc["health_check_service"] || "—"}
                </:item>
                <:item label="Allowed Services">{@service.grpc["allowed_services"] || "—"}</:item>
                <:item label="Allowed Methods">{@service.grpc["allowed_methods"] || "—"}</:item>
              </.definition_list>
            </div>
            <div :if={@service.service_type == "websocket" and @service.websocket != %{}}>
              <.definition_list>
                <:item label="Ping Interval">
                  {if @service.websocket["ping_interval"],
                    do: "#{@service.websocket["ping_interval"]}s",
                    else: "—"}
                </:item>
                <:item label="Max Message Size">
                  {@service.websocket["max_message_size"] || "—"}
                </:item>
                <:item label="Max Connections">
                  {@service.websocket["max_connections"] || "—"}
                </:item>
              </.definition_list>
            </div>
            <div :if={@service.service_type == "streaming" and @service.streaming != %{}}>
              <.definition_list>
                <:item label="Format">{@service.streaming["format"] || "—"}</:item>
                <:item label="Keepalive Interval">
                  {if @service.streaming["keepalive_interval"],
                    do: "#{@service.streaming["keepalive_interval"]}s",
                    else: "—"}
                </:item>
                <:item label="Max Connection Duration">
                  {if @service.streaming["max_connection_duration"],
                    do: "#{@service.streaming["max_connection_duration"]}s",
                    else: "—"}
                </:item>
                <:item label="Buffer Size">{@service.streaming["buffer_size"] || "—"}</:item>
              </.definition_list>
            </div>
            <div :if={@service.service_type == "inference" and @service.inference != %{}}>
              <.definition_list>
                <:item label="Provider">
                  <span class="badge badge-sm badge-outline">
                    {@service.inference["provider"] || "—"}
                  </span>
                </:item>
                <:item label="Tokens per Minute">
                  {@service.inference["tokens_per_minute"] || "—"}
                </:item>
                <:item label="Monthly Token Budget">
                  {@service.inference["monthly_token_budget"] || "—"}
                </:item>
                <:item label="Budget Alert Threshold">
                  {if @service.inference["budget_alert_threshold"],
                    do: "#{@service.inference["budget_alert_threshold"]}%",
                    else: "—"}
                </:item>
                <:item label="Streaming">
                  {if @service.inference["streaming_enabled"] in ["true", true],
                    do: "enabled",
                    else: "disabled"}
                </:item>
              </.definition_list>
            </div>
          </.k8s_section>
        </div>

        <div class="lg:col-span-2">
          <.k8s_section title="Middleware Chain">
            <div class="flex items-center justify-between mb-3">
              <p class="text-xs text-base-content/50">
                Middleware applied in position order after inline fields.
              </p>
              <form phx-submit="attach_middleware" class="flex gap-2 items-center">
                <select name="middleware_id" class="select select-bordered select-xs">
                  <option value="">Attach middleware...</option>
                  <option :for={mw <- @available_middlewares} value={mw.id}>
                    {mw.name} ({mw.middleware_type})
                  </option>
                </select>
                <button type="submit" class="btn btn-outline btn-xs">Attach</button>
              </form>
            </div>

            <table :if={@middleware_chain != []} class="table table-sm">
              <thead>
                <tr>
                  <th class="text-xs w-16">Position</th>
                  <th class="text-xs">Name</th>
                  <th class="text-xs">Type</th>
                  <th class="text-xs">Enabled</th>
                  <th class="text-xs">Override</th>
                  <th class="text-xs"></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={sm <- @middleware_chain}>
                  <td class="font-mono text-sm">{sm.position + 1}</td>
                  <td>{sm.middleware.name}</td>
                  <td>
                    <span class="badge badge-sm badge-outline">{sm.middleware.middleware_type}</span>
                  </td>
                  <td>
                    <span class={["badge badge-xs", (sm.enabled && "badge-success") || "badge-ghost"]}>
                      {if sm.enabled, do: "yes", else: "no"}
                    </span>
                  </td>
                  <td class="text-sm font-mono">
                    {if sm.config_override == %{}, do: "—", else: inspect(sm.config_override)}
                  </td>
                  <td>
                    <button
                      phx-click="detach_middleware"
                      phx-value-id={sm.id}
                      data-confirm="Detach this middleware?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Detach
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>

            <div :if={@middleware_chain == []} class="text-center py-4 text-base-content/50 text-sm">
              No middleware attached. Use the dropdown above to attach middleware from the library.
            </div>
          </.k8s_section>
        </div>

        <div class="lg:col-span-2">
          <.k8s_section title="KDL Preview">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto">{@kdl_preview}</pre>
          </.k8s_section>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_services_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp project_services_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

  defp service_edit_path(%{slug: org_slug}, project, service),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/#{service.id}/edit"

  defp service_edit_path(nil, project, service),
    do: ~p"/projects/#{project.slug}/services/#{service.id}/edit"

  defp generate_service_preview(service, config) do
    KdlGenerator.build_kdl([service], config)
  end

  defp format_map(nil), do: "—"
  defp format_map(map) when map == %{}, do: "—"

  defp format_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp format_traffic_split(nil), do: "—"
  defp format_traffic_split(ts) when ts == %{}, do: "—"

  defp format_traffic_split(ts) do
    splits = Map.get(ts, "splits", [])
    rules = Map.get(ts, "match_rules", [])

    parts = []

    parts =
      if splits != [] do
        split_desc =
          Enum.map_join(splits, ", ", fn s ->
            "#{s["upstream_group_id"] |> String.slice(0..7)}... (#{s["weight"]}%)"
          end)

        parts ++ ["Splits: #{split_desc}"]
      else
        parts
      end

    parts =
      if rules != [] do
        parts ++ ["#{length(rules)} match rule(s)"]
      else
        parts
      end

    if parts == [], do: "—", else: Enum.join(parts, " | ")
  end
end
