defmodule ZentinelCpWeb.SlosLive.Index do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Observability, Projects}

  @refresh_interval 30_000

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket), do: :timer.send_interval(@refresh_interval, :refresh)
        slos = Observability.list_slos(project.id)

        {:ok,
         assign(socket,
           page_title: "SLOs - #{project.name}",
           org: org,
           project: project,
           slos: slos
         )}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    slos = Observability.list_slos(socket.assigns.project.id)
    {:noreply, assign(socket, :slos, slos)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    slo = Observability.get_slo!(id)
    {:ok, _} = Observability.delete_slo(slo)

    {:noreply,
     socket
     |> put_flash(:info, "SLO deleted.")
     |> assign(:slos, Observability.list_slos(socket.assigns.project.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Service Level Objectives</h1>
        <.link navigate={new_slo_path(@org, @project)} class="btn btn-primary btn-sm">
          New SLO
        </.link>
      </div>

      <div :if={@slos == []} class="text-center py-12 text-base-content/50">
        <.icon name="hero-chart-pie" class="size-12 mx-auto mb-2 opacity-50" />
        <p>No SLOs defined yet.</p>
        <.link navigate={new_slo_path(@org, @project)} class="btn btn-outline btn-sm mt-4">
          Create your first SLO
        </.link>
      </div>

      <div :if={@slos != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div :for={slo <- @slos} class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4 space-y-3">
            <div class="flex items-center justify-between">
              <.link navigate={slo_path(@org, @project, slo)} class="font-semibold link">
                {slo.name}
              </.link>
              <.slo_status_badge status={Observability.slo_status(slo)} />
            </div>

            <div class="flex items-center gap-2 text-xs text-base-content/60">
              <span class="badge badge-xs badge-outline">{slo.sli_type}</span>
              <span>Target: {format_target(slo)}</span>
              <span>{slo.window_days}d window</span>
            </div>

            <div class="space-y-1">
              <div class="flex justify-between text-xs">
                <span>Error Budget</span>
                <span>{format_budget(slo.error_budget_remaining)}</span>
              </div>
              <progress
                class={["progress w-full", budget_color(slo.error_budget_remaining)]}
                value={budget_value(slo.error_budget_remaining)}
                max="100"
              >
              </progress>
            </div>

            <div class="flex justify-between text-xs text-base-content/50">
              <span>Burn Rate: {format_burn_rate(slo.burn_rate)}</span>
              <span :if={slo.last_computed_at}>
                Updated {Calendar.strftime(slo.last_computed_at, "%H:%M:%S")}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_target(%{sli_type: "availability"} = slo), do: "#{slo.target}%"
  defp format_target(%{sli_type: "error_rate"} = slo), do: "#{slo.target}%"

  defp format_target(%{sli_type: type} = slo) when type in ["latency_p99", "latency_p95"],
    do: "#{slo.target}ms"

  defp format_target(slo), do: "#{slo.target}"

  defp format_budget(nil), do: "N/A"
  defp format_budget(budget), do: "#{Float.round(budget, 1)}%"

  defp format_burn_rate(nil), do: "N/A"
  defp format_burn_rate(rate), do: "#{Float.round(rate, 2)}x"

  defp budget_value(nil), do: 100
  defp budget_value(budget), do: max(0, min(100, budget))

  defp budget_color(nil), do: "progress-success"
  defp budget_color(budget) when budget >= 50, do: "progress-success"
  defp budget_color(budget) when budget > 0, do: "progress-warning"
  defp budget_color(_), do: "progress-error"
end
