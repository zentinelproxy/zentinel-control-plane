defmodule SentinelCpWeb.TopologyLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Services}

  @refresh_interval 10_000

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          :timer.send_interval(@refresh_interval, self(), :refresh)
        end

        topology = Services.get_topology_data(project.id)

        {:ok,
         assign(socket,
           page_title: "Topology — #{project.name}",
           org: org,
           project: project,
           topology: topology
         )}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    topology = Services.get_topology_data(socket.assigns.project.id)
    {:noreply, push_event(socket, "topology-data", topology)}
  end

  @impl true
  def handle_event("navigate", %{"type" => type, "id" => id}, socket) do
    org = socket.assigns.org
    project = socket.assigns.project

    path =
      case type do
        "service" ->
          if org,
            do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/services/#{id}",
            else: ~p"/projects/#{project.slug}/services/#{id}"

        "upstream_group" ->
          if org,
            do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/upstream-groups/#{id}",
            else: ~p"/projects/#{project.slug}/upstream-groups/#{id}"

        "auth_policy" ->
          if org,
            do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/auth-policies/#{id}",
            else: ~p"/projects/#{project.slug}/auth-policies/#{id}"

        "certificate" ->
          if org,
            do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/certificates/#{id}",
            else: ~p"/projects/#{project.slug}/certificates/#{id}"

        "middleware" ->
          if org,
            do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/middlewares/#{id}",
            else: ~p"/projects/#{project.slug}/middlewares/#{id}"

        _ ->
          nil
      end

    if path do
      {:noreply, push_navigate(socket, to: path)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Service Topology</h1>
        </:filters>
        <:actions>
          <span class="text-xs text-base-content/50">Auto-refreshes every 10s</span>
        </:actions>
      </.table_toolbar>

      <div
        id="topology-graph"
        phx-hook="Topology"
        phx-update="ignore"
        data-topology={Jason.encode!(@topology)}
        class="w-full border border-base-300 rounded-lg bg-base-100 overflow-hidden"
        style="height: 600px;"
      >
        <div class="flex items-center justify-center h-full text-base-content/50">
          Loading topology...
        </div>
      </div>

      <div class="flex flex-wrap gap-4 text-xs text-base-content/60">
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 bg-primary rounded-sm inline-block"></span> Service
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 bg-secondary rounded-full inline-block"></span> Upstream Group
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 bg-accent rounded-sm rotate-45 inline-block"></span> Auth Policy
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 bg-warning rounded-sm inline-block"></span> Certificate
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 bg-info rounded-sm inline-block"></span> Middleware
        </span>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil
end
