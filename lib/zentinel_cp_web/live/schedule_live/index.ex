defmodule ZentinelCpWeb.ScheduleLive.Index do
  @moduledoc """
  LiveView for viewing scheduled rollouts in a timeline/calendar view.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Rollouts}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(60_000, self(), :refresh)
    end

    scheduled_rollouts = Rollouts.list_scheduled_rollouts()
    grouped = group_by_date(scheduled_rollouts)

    {:ok,
     assign(socket,
       page_title: "Scheduled Rollouts",
       scheduled_rollouts: scheduled_rollouts,
       grouped_rollouts: grouped
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    scheduled_rollouts = Rollouts.list_scheduled_rollouts()
    grouped = group_by_date(scheduled_rollouts)
    {:noreply, assign(socket, scheduled_rollouts: scheduled_rollouts, grouped_rollouts: grouped)}
  end

  defp group_by_date(rollouts) do
    rollouts
    |> Enum.group_by(fn r ->
      r.scheduled_at
      |> DateTime.to_date()
    end)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Scheduled Rollouts</h1>
        </:filters>
      </.table_toolbar>

      <div :if={@scheduled_rollouts == []} class="text-center py-12 text-base-content/50">
        <div class="text-4xl mb-4">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-16 w-16 mx-auto opacity-50"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
        </div>
        <p class="text-lg">No scheduled rollouts</p>
        <p class="mt-2 text-sm">Rollouts can be scheduled when creating them.</p>
      </div>

      <div :if={@scheduled_rollouts != []} class="space-y-6">
        <div class="stats shadow bg-base-200">
          <div class="stat">
            <div class="stat-title">Total Scheduled</div>
            <div class="stat-value text-primary">{length(@scheduled_rollouts)}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Next Rollout</div>
            <div class="stat-value text-sm">
              {format_relative_time(List.first(@scheduled_rollouts).scheduled_at)}
            </div>
            <div class="stat-desc">
              {Calendar.strftime(List.first(@scheduled_rollouts).scheduled_at, "%Y-%m-%d %H:%M UTC")}
            </div>
          </div>
        </div>

        <div :for={{date, rollouts} <- @grouped_rollouts} class="space-y-2">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 text-base-content/50"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
            {format_date(date)}
            <span class="badge badge-sm badge-ghost">{length(rollouts)} rollout(s)</span>
          </h2>

          <div class="ml-7 border-l-2 border-base-300 pl-4 space-y-3">
            <div
              :for={rollout <- Enum.sort_by(rollouts, & &1.scheduled_at, DateTime)}
              class="card bg-base-200 border border-base-300"
            >
              <div class="card-body p-4">
                <div class="flex flex-wrap items-start justify-between gap-4">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-2">
                      <span class="text-lg font-mono text-info">
                        {Calendar.strftime(rollout.scheduled_at, "%H:%M")}
                      </span>
                      <span class="text-base-content/50">UTC</span>
                      <.resource_badge type="rollout" />
                      <.link
                        navigate={rollout_path(rollout)}
                        class="font-mono text-primary hover:underline"
                      >
                        {String.slice(rollout.id, 0, 8)}
                      </.link>
                      <span
                        :if={rollout.approval_state == "pending_approval"}
                        class="badge badge-warning badge-sm"
                      >
                        awaiting approval
                      </span>
                      <span
                        :if={rollout.approval_state == "approved"}
                        class="badge badge-success badge-sm"
                      >
                        approved
                      </span>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-3 gap-2 text-sm">
                      <div>
                        <span class="text-base-content/50">Project:</span>
                        <span class="ml-1 font-medium">{rollout.project.name}</span>
                      </div>
                      <div>
                        <span class="text-base-content/50">Bundle:</span>
                        <span class="ml-1 font-mono">{rollout.bundle.version}</span>
                      </div>
                      <div>
                        <span class="text-base-content/50">Strategy:</span>
                        <span class="ml-1">{rollout.strategy}</span>
                      </div>
                    </div>

                    <div class="mt-1 text-sm">
                      <span class="text-base-content/50">Target:</span>
                      <span class="ml-1">{format_target(rollout.target_selector)}</span>
                    </div>
                  </div>

                  <div>
                    <.link
                      navigate={rollout_path(rollout)}
                      class="btn btn-ghost btn-sm"
                    >
                      Details
                    </.link>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp rollout_path(rollout) do
    project = rollout.project

    if project.org_id do
      org = Orgs.get_org!(project.org_id)
      ~p"/orgs/#{org.slug}/projects/#{project.slug}/rollouts/#{rollout.id}"
    else
      ~p"/projects/#{project.slug}/rollouts/#{rollout.id}"
    end
  end

  defp format_date(date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    cond do
      date == today -> "Today"
      date == tomorrow -> "Tomorrow"
      true -> Calendar.strftime(date, "%A, %B %d, %Y")
    end
  end

  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} specific node(s)"
  end

  defp format_target(%{"type" => "groups", "group_ids" => ids}) do
    "#{length(ids)} group(s)"
  end

  defp format_target(_), do: "—"

  defp format_relative_time(datetime) do
    diff = DateTime.diff(datetime, DateTime.utc_now(), :second)

    cond do
      diff < 60 -> "in #{diff}s"
      diff < 3600 -> "in #{div(diff, 60)}m"
      diff < 86400 -> "in #{div(diff, 3600)}h"
      true -> "in #{div(diff, 86400)}d"
    end
  end
end
