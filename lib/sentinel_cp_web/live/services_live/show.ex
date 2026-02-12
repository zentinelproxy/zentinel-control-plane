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

      {:ok,
       assign(socket,
         page_title: "Service #{service.name} — #{project.name}",
         org: org,
         project: project,
         service: service,
         auth_policy: auth_policy,
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
