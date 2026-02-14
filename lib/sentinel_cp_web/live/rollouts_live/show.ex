defmodule SentinelCpWeb.RolloutsLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Rollouts, Orgs, Projects, Nodes}
  alias SentinelCp.Projects.Project
  alias SentinelCp.Rollouts.CanaryAnalysis

  @refresh_interval 5_000

  @impl true
  def mount(%{"project_slug" => slug, "id" => rollout_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         rollout when not is_nil(rollout) <- Rollouts.get_rollout_with_details(rollout_id),
         true <- rollout.project_id == project.id do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(SentinelCp.PubSub, "rollout:#{rollout.id}")
        :timer.send_interval(@refresh_interval, self(), :refresh)
      end

      progress = Rollouts.get_rollout_progress(rollout.id)
      node_names = load_node_names(rollout.node_bundle_statuses)
      approvals = Rollouts.list_approvals(rollout.id)
      current_user = socket.assigns.current_user
      can_approve = can_user_approve?(rollout, current_user, project)

      {:ok,
       assign(socket,
         page_title: "Rollout — #{project.name}",
         org: org,
         project: project,
         rollout: rollout,
         progress: progress,
         node_names: node_names,
         approvals: approvals,
         can_approve: can_approve,
         show_reject_form: false,
         reject_comment: ""
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_event("pause", _, socket) do
    case Rollouts.pause_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout paused.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot pause rollout in current state.")}
    end
  end

  @impl true
  def handle_event("resume", _, socket) do
    case Rollouts.resume_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout resumed.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot resume rollout in current state.")}
    end
  end

  @impl true
  def handle_event("cancel", _, socket) do
    case Rollouts.cancel_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout cancelled.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot cancel rollout in current state.")}
    end
  end

  @impl true
  def handle_event("rollback", _, socket) do
    case Rollouts.rollback_rollout(socket.assigns.rollout) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(updated.id))
         |> put_flash(:info, "Rollout rolled back. Affected nodes reverted.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Cannot rollback rollout in current state.")}
    end
  end

  @impl true
  def handle_event("approve", _, socket) do
    case Rollouts.approve_rollout(socket.assigns.rollout, socket.assigns.current_user) do
      {:ok, updated} ->
        rollout = Rollouts.get_rollout_with_details(updated.id)
        approvals = Rollouts.list_approvals(rollout.id)

        socket =
          socket
          |> assign(rollout: rollout, approvals: approvals, can_approve: false)
          |> put_flash(:info, "Approval recorded.")

        # Auto-start if now approved and not scheduled
        cond do
          rollout.approval_state == "approved" and rollout.state == "pending" and
              rollout.scheduled_at != nil ->
            # Scheduled rollout - will start at scheduled time
            {:noreply,
             put_flash(
               socket,
               :info,
               "Rollout approved. Will start at #{Calendar.strftime(rollout.scheduled_at, "%Y-%m-%d %H:%M UTC")}."
             )}

          rollout.approval_state == "approved" and rollout.state == "pending" ->
            case Rollouts.plan_rollout(rollout) do
              {:ok, _} ->
                rollout = Rollouts.get_rollout_with_details(rollout.id)

                {:noreply,
                 assign(socket, rollout: rollout)
                 |> put_flash(:info, "Rollout approved and started.")}

              {:error, :no_target_nodes} ->
                {:noreply,
                 put_flash(socket, :error, "Rollout approved but no target nodes found.")}

              {:error, reason} ->
                {:noreply,
                 put_flash(
                   socket,
                   :error,
                   "Rollout approved but failed to start: #{inspect(reason)}"
                 )}
            end

          true ->
            {:noreply, socket}
        end

      {:error, :self_approval} ->
        {:noreply, put_flash(socket, :error, "Cannot approve your own rollout.")}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve rollouts.")}

      {:error, :already_approved} ->
        {:noreply, put_flash(socket, :error, "You have already approved this rollout.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Rollout is not awaiting approval.")}
    end
  end

  @impl true
  def handle_event("show_reject_form", _, socket) do
    {:noreply, assign(socket, show_reject_form: true)}
  end

  @impl true
  def handle_event("hide_reject_form", _, socket) do
    {:noreply, assign(socket, show_reject_form: false, reject_comment: "")}
  end

  @impl true
  def handle_event("reject", %{"comment" => comment}, socket) do
    case Rollouts.reject_rollout(socket.assigns.rollout, socket.assigns.current_user, comment) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(
           rollout: Rollouts.get_rollout_with_details(updated.id),
           show_reject_form: false,
           reject_comment: ""
         )
         |> put_flash(:info, "Rollout rejected.")}

      {:error, :comment_required} ->
        {:noreply, put_flash(socket, :error, "A comment is required when rejecting.")}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to reject rollouts.")}

      {:error, :invalid_state} ->
        {:noreply, put_flash(socket, :error, "Rollout is not awaiting approval.")}
    end
  end

  @impl true
  def handle_event("start", _, socket) do
    rollout = socket.assigns.rollout

    case Rollouts.plan_rollout(rollout) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(rollout: Rollouts.get_rollout_with_details(rollout.id))
         |> put_flash(:info, "Rollout started.")}

      {:error, :no_target_nodes} ->
        {:noreply, put_flash(socket, :error, "No target nodes matched the selector.")}

      {:error, :approval_required} ->
        {:noreply, put_flash(socket, :error, "Rollout requires approval before starting.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start rollout: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:rollout_updated, _rollout_id}, socket) do
    reload(socket)
  end

  @impl true
  def handle_info(:refresh, socket) do
    if socket.assigns.rollout.state in ~w(running paused) do
      reload(socket)
    else
      {:noreply, socket}
    end
  end

  defp reload(socket) do
    rollout = Rollouts.get_rollout_with_details(socket.assigns.rollout.id)
    progress = Rollouts.get_rollout_progress(rollout.id)
    node_names = load_node_names(rollout.node_bundle_statuses)
    approvals = Rollouts.list_approvals(rollout.id)
    can_approve = can_user_approve?(rollout, socket.assigns.current_user, socket.assigns.project)

    {:noreply,
     assign(socket,
       rollout: rollout,
       progress: progress,
       node_names: node_names,
       approvals: approvals,
       can_approve: can_approve
     )}
  end

  defp load_node_names(node_bundle_statuses) do
    node_ids = Enum.map(node_bundle_statuses, & &1.node_id)

    if node_ids == [] do
      %{}
    else
      node_ids
      |> Enum.map(fn id ->
        case Nodes.get_node(id) do
          nil -> {id, "unknown"}
          node -> {id, node.name}
        end
      end)
      |> Map.new()
    end
  end

  defp can_user_approve?(rollout, user, project) do
    cond do
      # Not in pending_approval state
      rollout.approval_state != "pending_approval" ->
        false

      # No user (shouldn't happen but handle it)
      is_nil(user) ->
        false

      # Creator cannot self-approve
      rollout.created_by_id == user.id ->
        false

      # Check if user has already approved
      Rollouts.count_approvals(rollout.id) > 0 and
          Enum.any?(Rollouts.list_approvals(rollout.id), &(&1.user_id == user.id)) ->
        false

      # Check org role
      true ->
        Orgs.user_has_role?(project.org_id, user.id, "operator")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={"Rollout " <> String.slice(@rollout.id, 0, 8)}
        resource_type="rollout"
        back_path={project_rollouts_path(@org, @project)}
      >
        <:badge>
          <span
            class={[
              "badge badge-sm",
              @rollout.state == "completed" && "badge-success",
              @rollout.state == "running" && "badge-warning",
              @rollout.state == "failed" && "badge-error",
              @rollout.state == "cancelled" && "badge-error",
              @rollout.state == "paused" && "badge-info",
              @rollout.state == "pending" && "badge-ghost"
            ]}
            data-testid="rollout-state"
          >
            {@rollout.state}
          </span>
          <span
            :if={@rollout.approval_state == "pending_approval"}
            class="badge badge-sm badge-warning"
          >
            awaiting approval
          </span>
          <span :if={@rollout.approval_state == "rejected"} class="badge badge-sm badge-error">
            rejected
          </span>
          <span :if={@rollout.approval_state == "approved"} class="badge badge-sm badge-success">
            approved
          </span>
          <span
            :if={@rollout.state == "pending" and @rollout.scheduled_at}
            class="badge badge-sm badge-info"
          >
            scheduled
          </span>
        </:badge>
        <:action>
          <button
            :if={@rollout.state == "pending" and @rollout.approval_state == "approved"}
            class="btn btn-primary btn-sm"
            phx-click="start"
          >
            Start
          </button>
          <button :if={@rollout.state == "running"} class="btn btn-warning btn-sm" phx-click="pause">
            Pause
          </button>
          <button :if={@rollout.state == "paused"} class="btn btn-primary btn-sm" phx-click="resume">
            Resume
          </button>
          <button
            :if={@rollout.state in ~w(running paused)}
            class="btn btn-error btn-sm"
            phx-click="cancel"
          >
            Cancel
          </button>
          <button
            :if={@rollout.state in ~w(running paused)}
            class="btn btn-outline btn-error btn-sm"
            phx-click="rollback"
          >
            Rollback
          </button>
          <button
            :if={@rollout.state == "pending" and @rollout.approval_state == "rejected"}
            class="btn btn-error btn-sm"
            phx-click="cancel"
          >
            Cancel
          </button>
        </:action>
      </.detail_header>

      <div data-testid="rollout-progress">
        <.stat_strip>
          <:stat label="Total" value={to_string(@progress.total)} />
          <:stat label="Active" value={to_string(@progress.active)} color="success" />
          <:stat label="Pending" value={to_string(@progress.pending)} />
          <:stat label="Failed" value={to_string(@progress.failed)} color="error" />
        </.stat_strip>
      </div>

      <%!-- Approval Required Panel --%>
      <div :if={@rollout.approval_state == "pending_approval"}>
        <.k8s_section title="Approval Required">
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <div class="text-sm">
                <span class="font-semibold">{length(@approvals)}</span>
                / {approvals_needed(@project)} approvals
              </div>
              <div class="flex gap-2">
                <button
                  :if={@can_approve}
                  class="btn btn-primary btn-sm"
                  phx-click="approve"
                >
                  Approve
                </button>
                <button
                  :if={@can_approve and not @show_reject_form}
                  class="btn btn-error btn-outline btn-sm"
                  phx-click="show_reject_form"
                >
                  Reject
                </button>
              </div>
            </div>

            <div
              :if={@can_approve == false and @rollout.created_by_id == @current_user.id}
              class="text-sm text-warning"
            >
              You cannot approve your own rollout.
            </div>

            <%!-- Rejection Form --%>
            <div :if={@show_reject_form} class="border border-error/30 bg-error/5 rounded p-4">
              <form phx-submit="reject" class="space-y-2">
                <label class="label">
                  <span class="label-text">Rejection comment (required)</span>
                </label>
                <textarea
                  name="comment"
                  class="textarea textarea-bordered w-full"
                  placeholder="Explain why this rollout is being rejected..."
                  rows="3"
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

            <%!-- Existing Approvals --%>
            <div :if={@approvals != []} class="border-t pt-4">
              <div class="text-sm font-semibold mb-2">Approvals</div>
              <ul class="space-y-1">
                <li :for={approval <- @approvals} class="text-sm flex items-center gap-2">
                  <span class="badge badge-success badge-xs"></span>
                  <span>{approval.user.email}</span>
                  <span class="text-base-content/50">
                    {Calendar.strftime(approval.approved_at, "%Y-%m-%d %H:%M")}
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </.k8s_section>
      </div>

      <%!-- Rejection Panel --%>
      <div :if={@rollout.approval_state == "rejected"}>
        <div class="alert alert-error">
          <div>
            <div class="font-semibold">Rollout Rejected</div>
            <div class="text-sm mt-1">{@rollout.rejection_comment}</div>
            <div :if={@rollout.rejected_at} class="text-xs mt-1 opacity-70">
              Rejected at {Calendar.strftime(@rollout.rejected_at, "%Y-%m-%d %H:%M:%S UTC")}
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@rollout.id}</span></:item>
            <:item label="Bundle"><span class="font-mono text-sm">{@rollout.bundle_id}</span></:item>
            <:item label="Strategy">{@rollout.strategy}</:item>
            <:item label="Batch Size">{@rollout.batch_size}</:item>
            <:item label="Target">{format_target(@rollout.target_selector)}</:item>
            <:item :if={@rollout.scheduled_at} label="Scheduled">
              <span class="text-info">
                {Calendar.strftime(@rollout.scheduled_at, "%Y-%m-%d %H:%M:%S UTC")}
              </span>
            </:item>
            <:item label="Started">
              {if @rollout.started_at,
                do: Calendar.strftime(@rollout.started_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Completed">
              {if @rollout.completed_at,
                do: Calendar.strftime(@rollout.completed_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
          </.definition_list>
        </.k8s_section>

        <div :if={@rollout.error}>
          <.k8s_section title="Error">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap">{Jason.encode!(@rollout.error, pretty: true)}</pre>
          </.k8s_section>
        </div>
      </div>

      <div :if={@rollout.strategy == "canary"}>
        <.k8s_section title="Canary Analysis" testid="canary-analysis">
          <div class="space-y-4">
            <div class="flex items-center gap-4">
              <div class="text-sm">
                <span class="font-semibold">Step {(@rollout.canary_step_index || 0) + 1}</span>
                <span class="text-base-content/50">
                  — {canary_step_pct(@rollout)}% traffic
                </span>
              </div>
              <div :if={latest_canary_decision(@rollout)}>
                <span class={[
                  "badge badge-sm",
                  latest_canary_decision(@rollout) == "promote" && "badge-success",
                  latest_canary_decision(@rollout) == "rollback" && "badge-error",
                  latest_canary_decision(@rollout) == "extend" && "badge-warning"
                ]}>
                  {latest_canary_decision(@rollout)}
                </span>
              </div>
            </div>

            <div :if={latest_canary_analysis(@rollout)} class="overflow-x-auto">
              <table class="table table-sm">
                <thead class="bg-base-300">
                  <tr>
                    <th class="text-xs uppercase">Metric</th>
                    <th class="text-xs uppercase">Canary</th>
                    <th class="text-xs uppercase">Baseline</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td class="text-sm">Error Rate</td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["canary", "error_rate"])
                      |> format_number()}%
                    </td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["baseline", "error_rate"])
                      |> format_number()}%
                    </td>
                  </tr>
                  <tr>
                    <td class="text-sm">Latency P99</td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["canary", "avg_latency_p99"])
                      |> format_number()} ms
                    </td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["baseline", "avg_latency_p99"])
                      |> format_number()} ms
                    </td>
                  </tr>
                  <tr>
                    <td class="text-sm">Requests</td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["canary", "total_requests"]) || 0}
                    </td>
                    <td class="font-mono text-sm">
                      {get_in(latest_canary_analysis(@rollout), ["baseline", "total_requests"]) || 0}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div :if={canary_analysis_history(@rollout) != []} class="border-t pt-3">
              <h4 class="text-xs font-semibold mb-2">Analysis History</h4>
              <div class="space-y-1">
                <div
                  :for={analysis <- canary_analysis_history(@rollout)}
                  class="flex items-center gap-2 text-xs"
                >
                  <span class={[
                    "badge badge-xs",
                    analysis["decision"] == "promote" && "badge-success",
                    to_string(analysis["decision"]) == "rollback" && "badge-error",
                    to_string(analysis["decision"]) == "extend" && "badge-warning"
                  ]}>
                    {analysis["decision"]}
                  </span>
                  <span class="text-base-content/50">{analysis["analyzed_at"]}</span>
                </div>
              </div>
            </div>

            <div :if={latest_canary_analysis(@rollout) == nil} class="text-sm text-base-content/50">
              No canary analysis results yet. Analysis begins after the first step reaches the verifying state.
            </div>
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Steps" testid="rollout-steps">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Step</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Nodes</th>
              <th class="text-xs uppercase">Started</th>
              <th class="text-xs uppercase">Completed</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={step <- @rollout.steps}>
              <td>{step.step_index + 1}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  step.state == "completed" && "badge-success",
                  step.state == "running" && "badge-warning",
                  step.state == "verifying" && "badge-info",
                  step.state == "failed" && "badge-error",
                  step.state == "pending" && "badge-ghost"
                ]}>
                  {step.state}
                </span>
              </td>
              <td>{length(step.node_ids)}</td>
              <td class="text-sm">
                {if step.started_at, do: Calendar.strftime(step.started_at, "%H:%M:%S"), else: "—"}
              </td>
              <td class="text-sm">
                {if step.completed_at, do: Calendar.strftime(step.completed_at, "%H:%M:%S"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@rollout.steps == []} class="text-base-content/50 text-sm py-4">
          No steps created yet.
        </div>
      </.k8s_section>

      <.k8s_section title="Node Statuses">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Node</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Staged</th>
              <th class="text-xs uppercase">Activated</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={nbs <- @rollout.node_bundle_statuses}>
              <td>
                <.link
                  navigate={node_show_path(@org, @project, nbs.node_id)}
                  class="flex items-center gap-2 text-primary hover:underline"
                >
                  <.resource_badge type="node" />
                  {Map.get(@node_names, nbs.node_id, nbs.node_id |> String.slice(0, 8))}
                </.link>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  nbs.state == "active" && "badge-success",
                  nbs.state in ~w(staging activating) && "badge-warning",
                  nbs.state == "failed" && "badge-error",
                  nbs.state == "pending" && "badge-ghost"
                ]}>
                  {nbs.state}
                </span>
              </td>
              <td class="text-sm">
                {if nbs.staged_at, do: Calendar.strftime(nbs.staged_at, "%H:%M:%S"), else: "—"}
              </td>
              <td class="text-sm">
                {if nbs.activated_at, do: Calendar.strftime(nbs.activated_at, "%H:%M:%S"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@rollout.node_bundle_statuses == []} class="text-base-content/50 text-sm py-4">
          No node statuses yet.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp project_rollouts_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts"

  defp project_rollouts_path(nil, project),
    do: ~p"/projects/#{project.slug}/rollouts"

  defp node_show_path(%{slug: org_slug}, project, node_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node_id}"

  defp node_show_path(nil, project, node_id),
    do: ~p"/projects/#{project.slug}/nodes/#{node_id}"

  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} node(s)"
  end

  defp format_target(_), do: "—"

  defp approvals_needed(project) do
    Project.approvals_needed(project)
  end

  defp canary_step_pct(rollout) do
    CanaryAnalysis.current_step_percentage(
      rollout.canary_analysis_config,
      rollout.canary_step_index || 0
    )
  end

  defp latest_canary_analysis(rollout) do
    case rollout.canary_analysis_results do
      %{"analyses" => [_ | _] = analyses} -> List.last(analyses)
      _ -> nil
    end
  end

  defp latest_canary_decision(rollout) do
    case latest_canary_analysis(rollout) do
      %{"decision" => decision} -> to_string(decision)
      _ -> nil
    end
  end

  defp canary_analysis_history(rollout) do
    case rollout.canary_analysis_results do
      %{"analyses" => analyses} when is_list(analyses) -> analyses
      _ -> []
    end
  end

  defp format_number(nil), do: "0"
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_number(n), do: to_string(n)
end
