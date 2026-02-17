defmodule ZentinelCpWeb.SlosLive.Show do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Audit, Observability, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         slo when not is_nil(slo) <- Observability.get_slo(id),
         true <- slo.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "#{slo.name} - #{project.name}",
         org: org,
         project: project,
         slo: slo
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", _, socket) do
    slo = socket.assigns.slo
    {:ok, updated} = Observability.update_slo(slo, %{enabled: !slo.enabled})

    {:noreply, assign(socket, :slo, updated)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    slo = socket.assigns.slo
    project = socket.assigns.project

    {:ok, _} = Observability.delete_slo(slo)

    Audit.log_user_action(
      socket.assigns.current_user,
      "delete",
      "slo",
      slo.id,
      project_id: project.id
    )

    {:noreply,
     socket
     |> put_flash(:info, "SLO deleted.")
     |> push_navigate(to: slos_path(socket.assigns.org, project))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@slo.name}
        resource_type="SLO"
        back_path={slos_path(@org, @project)}
      >
        <:badge>
          <.slo_status_badge status={Observability.slo_status(@slo)} />
          <span class="badge badge-sm badge-outline">{@slo.sli_type}</span>
          <span class={["badge badge-sm", (@slo.enabled && "badge-success") || "badge-ghost"]}>
            {if @slo.enabled, do: "enabled", else: "disabled"}
          </span>
        </:badge>
        <:action>
          <button phx-click="toggle_enabled" class="btn btn-outline btn-sm">
            {if @slo.enabled, do: "Disable", else: "Enable"}
          </button>
          <.link navigate={edit_slo_path(@org, @project, @slo)} class="btn btn-outline btn-sm">
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this SLO?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="Name">{@slo.name}</:item>
            <:item label="Description">{@slo.description || "—"}</:item>
            <:item label="SLI Type">
              <span class="badge badge-sm badge-outline">{@slo.sli_type}</span>
            </:item>
            <:item label="Target">{format_target(@slo)}</:item>
            <:item label="Window">{@slo.window_days} days</:item>
            <:item label="Created">
              {Calendar.strftime(@slo.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Current Status">
          <div class="space-y-4">
            <div class="stat">
              <div class="stat-title">Error Budget Remaining</div>
              <div class={["stat-value text-2xl", budget_text_color(@slo.error_budget_remaining)]}>
                {format_budget(@slo.error_budget_remaining)}
              </div>
            </div>

            <progress
              class={["progress w-full h-4", budget_color(@slo.error_budget_remaining)]}
              value={budget_value(@slo.error_budget_remaining)}
              max="100"
            >
            </progress>

            <div class="grid grid-cols-2 gap-4 pt-2">
              <div>
                <div class="text-xs text-base-content/50">Burn Rate</div>
                <div class={["text-lg font-bold", burn_rate_color(@slo.burn_rate)]}>
                  {format_burn_rate(@slo.burn_rate)}
                </div>
              </div>
              <div>
                <div class="text-xs text-base-content/50">Last Computed</div>
                <div class="text-sm">
                  {if @slo.last_computed_at,
                    do: Calendar.strftime(@slo.last_computed_at, "%Y-%m-%d %H:%M:%S"),
                    else: "Never"}
                </div>
              </div>
            </div>
          </div>
        </.k8s_section>
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

  defp budget_text_color(nil), do: "text-success"
  defp budget_text_color(budget) when budget >= 50, do: "text-success"
  defp budget_text_color(budget) when budget > 0, do: "text-warning"
  defp budget_text_color(_), do: "text-error"

  defp burn_rate_color(nil), do: ""
  defp burn_rate_color(rate) when rate <= 1.0, do: "text-success"
  defp burn_rate_color(rate) when rate <= 2.0, do: "text-warning"
  defp burn_rate_color(_), do: "text-error"
end
