defmodule ZentinelCpWeb.ApprovalsLive.Index do
  @moduledoc """
  LiveView for the approval queue - shows all rollouts pending approval.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Rollouts}
  alias ZentinelCp.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to rollout updates across all projects
      Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "rollouts:approvals")
    end

    pending_rollouts = Rollouts.list_pending_approvals()
    current_user = socket.assigns.current_user

    # Enrich with approval info
    pending_rollouts =
      Enum.map(pending_rollouts, fn rollout ->
        approvals = Rollouts.list_approvals(rollout.id)
        approvals_needed = get_approvals_needed(rollout.project)
        can_approve = can_user_approve?(rollout, current_user, rollout.project)

        %{
          rollout: rollout,
          approvals: approvals,
          approvals_needed: approvals_needed,
          can_approve: can_approve
        }
      end)

    {:ok,
     assign(socket,
       page_title: "Approval Queue",
       pending_rollouts: pending_rollouts,
       show_reject_form: nil
     )}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    rollout = Rollouts.get_rollout!(id)
    current_user = socket.assigns.current_user

    case Rollouts.approve_rollout(rollout, current_user) do
      {:ok, updated} ->
        # Check if rollout is now fully approved and should start
        updated = Rollouts.get_rollout_with_details(updated.id)

        socket =
          if updated.approval_state == "approved" and updated.state == "pending" and
               is_nil(updated.scheduled_at) do
            case Rollouts.plan_rollout(updated) do
              {:ok, _} ->
                put_flash(socket, :info, "Rollout approved and started.")

              {:error, reason} ->
                put_flash(socket, :warning, "Approved but failed to start: #{inspect(reason)}")
            end
          else
            put_flash(socket, :info, "Approval recorded.")
          end

        {:noreply, socket |> reload_pending()}

      {:error, :self_approval} ->
        {:noreply, put_flash(socket, :error, "Cannot approve your own rollout.")}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve rollouts.")}

      {:error, :already_approved} ->
        {:noreply, put_flash(socket, :error, "You have already approved this rollout.")}

      {:error, :invalid_state} ->
        {:noreply,
         socket
         |> put_flash(:error, "Rollout is no longer awaiting approval.")
         |> reload_pending()}
    end
  end

  @impl true
  def handle_event("show_reject_form", %{"id" => id}, socket) do
    {:noreply, assign(socket, show_reject_form: id)}
  end

  @impl true
  def handle_event("hide_reject_form", _, socket) do
    {:noreply, assign(socket, show_reject_form: nil)}
  end

  @impl true
  def handle_event("reject", %{"rollout_id" => id, "comment" => comment}, socket) do
    rollout = Rollouts.get_rollout!(id)
    current_user = socket.assigns.current_user

    case Rollouts.reject_rollout(rollout, current_user, comment) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(show_reject_form: nil)
         |> put_flash(:info, "Rollout rejected.")
         |> reload_pending()}

      {:error, :comment_required} ->
        {:noreply, put_flash(socket, :error, "A comment is required when rejecting.")}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to reject rollouts.")}

      {:error, :invalid_state} ->
        {:noreply,
         socket
         |> put_flash(:error, "Rollout is no longer awaiting approval.")
         |> reload_pending()}
    end
  end

  @impl true
  def handle_info({:rollout_approval_update, _rollout_id}, socket) do
    {:noreply, reload_pending(socket)}
  end

  defp reload_pending(socket) do
    current_user = socket.assigns.current_user
    pending_rollouts = Rollouts.list_pending_approvals()

    pending_rollouts =
      Enum.map(pending_rollouts, fn rollout ->
        approvals = Rollouts.list_approvals(rollout.id)
        approvals_needed = get_approvals_needed(rollout.project)
        can_approve = can_user_approve?(rollout, current_user, rollout.project)

        %{
          rollout: rollout,
          approvals: approvals,
          approvals_needed: approvals_needed,
          can_approve: can_approve
        }
      end)

    assign(socket, pending_rollouts: pending_rollouts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Approval Queue</h1>
        </:filters>
      </.table_toolbar>

      <div :if={@pending_rollouts == []} class="text-center py-12 text-base-content/50">
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
              d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>
        <p class="text-lg">No rollouts pending approval</p>
        <p class="mt-2 text-sm">All clear! Check back later.</p>
      </div>

      <div :if={@pending_rollouts != []} class="space-y-4">
        <div
          :for={item <- @pending_rollouts}
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-4">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-2">
                  <.resource_badge type="rollout" />
                  <.link
                    navigate={rollout_path(item.rollout)}
                    class="font-mono text-primary hover:underline"
                  >
                    {String.slice(item.rollout.id, 0, 8)}
                  </.link>
                  <span class="badge badge-warning badge-sm">awaiting approval</span>
                  <span :if={item.rollout.scheduled_at} class="badge badge-info badge-sm">
                    scheduled
                  </span>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                  <div>
                    <span class="text-base-content/50">Project:</span>
                    <span class="ml-1 font-medium">{item.rollout.project.name}</span>
                  </div>
                  <div>
                    <span class="text-base-content/50">Bundle:</span>
                    <span class="ml-1 font-mono">{item.rollout.bundle.version}</span>
                  </div>
                  <div>
                    <span class="text-base-content/50">Strategy:</span>
                    <span class="ml-1">{item.rollout.strategy}</span>
                  </div>
                </div>

                <div class="mt-2 text-sm">
                  <span class="text-base-content/50">Target:</span>
                  <span class="ml-1">{format_target(item.rollout.target_selector)}</span>
                </div>

                <div :if={item.rollout.scheduled_at} class="mt-2 text-sm">
                  <span class="text-base-content/50">Scheduled for:</span>
                  <span class="ml-1 text-info">
                    {Calendar.strftime(item.rollout.scheduled_at, "%Y-%m-%d %H:%M UTC")}
                  </span>
                </div>

                <div class="mt-2 text-sm text-base-content/50">
                  Created {format_relative_time(item.rollout.inserted_at)}
                  {if item.rollout.created_by_id, do: "by a team member", else: ""}
                </div>
              </div>

              <div class="flex flex-col items-end gap-2">
                <div class="text-sm">
                  <span class="font-semibold">{length(item.approvals)}</span>
                  <span class="text-base-content/50">/ {item.approvals_needed} approvals</span>
                </div>

                <div class="flex gap-2">
                  <button
                    :if={item.can_approve}
                    class="btn btn-primary btn-sm"
                    phx-click="approve"
                    phx-value-id={item.rollout.id}
                  >
                    Approve
                  </button>
                  <button
                    :if={item.can_approve and @show_reject_form != item.rollout.id}
                    class="btn btn-error btn-outline btn-sm"
                    phx-click="show_reject_form"
                    phx-value-id={item.rollout.id}
                  >
                    Reject
                  </button>
                  <.link
                    navigate={rollout_path(item.rollout)}
                    class="btn btn-ghost btn-sm"
                  >
                    Details
                  </.link>
                </div>

                <div
                  :if={!item.can_approve and item.rollout.created_by_id == @current_user.id}
                  class="text-xs text-warning"
                >
                  Cannot approve own rollout
                </div>
              </div>
            </div>

            <%!-- Existing Approvals --%>
            <div :if={item.approvals != []} class="mt-3 pt-3 border-t border-base-300">
              <div class="text-xs text-base-content/50 mb-1">Approved by:</div>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={approval <- item.approvals}
                  class="badge badge-success badge-sm gap-1"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-3 w-3"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {approval.user.email}
                </span>
              </div>
            </div>

            <%!-- Rejection Form --%>
            <div
              :if={@show_reject_form == item.rollout.id}
              class="mt-3 pt-3 border-t border-error/30 bg-error/5 rounded p-3"
            >
              <form phx-submit="reject" class="space-y-2">
                <input type="hidden" name="rollout_id" value={item.rollout.id} />
                <label class="label">
                  <span class="label-text">Rejection comment (required)</span>
                </label>
                <textarea
                  name="comment"
                  class="textarea textarea-bordered w-full"
                  placeholder="Explain why this rollout is being rejected..."
                  rows="2"
                  required
                />
                <div class="flex gap-2 justify-end">
                  <button type="button" class="btn btn-ghost btn-sm" phx-click="hide_reject_form">
                    Cancel
                  </button>
                  <button type="submit" class="btn btn-error btn-sm">
                    Reject Rollout
                  </button>
                </div>
              </form>
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

  defp get_approvals_needed(project) do
    Project.approvals_needed(project)
  end

  defp can_user_approve?(rollout, user, project) do
    cond do
      is_nil(user) ->
        false

      # Creator cannot self-approve
      rollout.created_by_id == user.id ->
        false

      # Check if user has already approved
      Enum.any?(Rollouts.list_approvals(rollout.id), &(&1.user_id == user.id)) ->
        false

      # Check org role
      true ->
        Orgs.user_has_role?(project.org_id, user.id, "operator")
    end
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
