defmodule SentinelCp.Rollouts do
  @moduledoc """
  The Rollouts context handles bundle deployment orchestration.

  Rollouts progress through batched steps, assigning bundles to target nodes
  with health gates and support for pause/resume/cancel/rollback.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo

  alias SentinelCp.Rollouts.{
    Rollout,
    RolloutStep,
    NodeBundleStatus,
    RolloutApproval,
    RolloutTemplate,
    TickWorker,
    HealthCheckEndpoint,
    HealthChecker
  }

  alias SentinelCp.Rollouts.CanaryAnalysis
  alias SentinelCp.{Bundles, Nodes, Orgs, Projects}
  # Events module replaces Notifications with backward-compatible API
  alias SentinelCp.Events, as: Notifications

  ## Rollout Template CRUD

  @doc """
  Creates a rollout template.
  """
  def create_template(attrs) do
    %RolloutTemplate{}
    |> RolloutTemplate.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a rollout template.
  """
  def update_template(%RolloutTemplate{} = template, attrs) do
    template
    |> RolloutTemplate.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a rollout template.
  """
  def delete_template(%RolloutTemplate{} = template) do
    Repo.delete(template)
  end

  @doc """
  Gets a rollout template by ID.
  """
  def get_template(id), do: Repo.get(RolloutTemplate, id)

  @doc """
  Gets a rollout template by ID, raises if not found.
  """
  def get_template!(id), do: Repo.get!(RolloutTemplate, id)

  @doc """
  Lists all templates for a project, ordered: default first, then by name.
  """
  def list_templates(project_id) do
    from(t in RolloutTemplate,
      where: t.project_id == ^project_id,
      order_by: [desc: t.is_default, asc: t.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets the default template for a project.
  """
  def get_default_template(project_id) do
    from(t in RolloutTemplate,
      where: t.project_id == ^project_id and t.is_default == true
    )
    |> Repo.one()
  end

  @doc """
  Sets a template as the default for its project.
  Unsets any existing default in the same project.
  """
  def set_default_template(%RolloutTemplate{} = template) do
    Repo.transaction(fn ->
      # Clear existing default
      from(t in RolloutTemplate,
        where: t.project_id == ^template.project_id and t.is_default == true
      )
      |> Repo.update_all(set: [is_default: false])

      # Set this template as default
      {:ok, updated} =
        template
        |> Ecto.Changeset.change(is_default: true)
        |> Repo.update()

      updated
    end)
  end

  @doc """
  Clears the default template for a project.
  """
  def clear_default_template(project_id) do
    from(t in RolloutTemplate,
      where: t.project_id == ^project_id and t.is_default == true
    )
    |> Repo.update_all(set: [is_default: false])

    :ok
  end

  @doc """
  Returns a changeset for tracking template changes.
  """
  def change_template(%RolloutTemplate{} = template, attrs \\ %{}) do
    RolloutTemplate.update_changeset(template, attrs)
  end

  ## Health Check Endpoint CRUD

  @doc """
  Lists all health check endpoints for a project.
  """
  def list_health_check_endpoints(project_id) do
    from(e in HealthCheckEndpoint,
      where: e.project_id == ^project_id,
      order_by: [asc: e.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a health check endpoint by ID.
  """
  def get_health_check_endpoint(id), do: Repo.get(HealthCheckEndpoint, id)

  @doc """
  Gets a health check endpoint by ID, raises if not found.
  """
  def get_health_check_endpoint!(id), do: Repo.get!(HealthCheckEndpoint, id)

  @doc """
  Creates a health check endpoint.
  """
  def create_health_check_endpoint(attrs) do
    %HealthCheckEndpoint{}
    |> HealthCheckEndpoint.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a health check endpoint.
  """
  def update_health_check_endpoint(%HealthCheckEndpoint{} = endpoint, attrs) do
    endpoint
    |> HealthCheckEndpoint.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a health check endpoint.
  """
  def delete_health_check_endpoint(%HealthCheckEndpoint{} = endpoint) do
    Repo.delete(endpoint)
  end

  @doc """
  Tests a health check endpoint.
  """
  def test_health_check_endpoint(%HealthCheckEndpoint{} = endpoint) do
    HealthChecker.check(endpoint)
  end

  ## Rollout CRUD

  @doc """
  Creates a rollout. Validates that the bundle is compiled and
  no freeze window is active for the target environment.
  """
  def create_rollout(attrs, opts \\ []) do
    changeset = Rollout.create_changeset(%Rollout{}, attrs)
    override_freeze = Keyword.get(opts, :override_freeze, false)

    with :ok <- check_freeze_window(changeset, override_freeze),
         {:ok, changeset} <- validate_bundle_compiled(changeset),
         {:ok, rollout} <- Repo.insert(changeset) do
      {:ok, rollout}
    end
  end

  defp check_freeze_window(_changeset, true), do: :ok

  defp check_freeze_window(changeset, false) do
    project_id = Ecto.Changeset.get_field(changeset, :project_id)
    environment_id = Ecto.Changeset.get_field(changeset, :environment_id)

    case active_freeze_window(project_id, environment_id) do
      nil -> :ok
      window -> {:error, {:freeze_window_active, window}}
    end
  end

  @doc """
  Returns the currently active freeze window for a project/environment, if any.
  """
  def active_freeze_window(nil, _environment_id), do: nil

  def active_freeze_window(project_id, environment_id) do
    now = DateTime.utc_now()

    query =
      from(w in SentinelCp.Rollouts.FreezeWindow,
        where:
          w.project_id == ^project_id and
            w.starts_at <= ^now and
            w.ends_at >= ^now
      )

    query =
      if environment_id do
        where(query, [w], is_nil(w.environment_id) or w.environment_id == ^environment_id)
      else
        query
      end

    Repo.one(query)
  end

  @doc """
  Lists rollouts for a project, ordered by most recent first.
  """
  def list_rollouts(project_id, opts \\ []) do
    query =
      from(r in Rollout,
        where: r.project_id == ^project_id,
        order_by: [desc: r.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:state, state}, q -> where(q, [r], r.state == ^state)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a rollout by ID.
  """
  def get_rollout(id), do: Repo.get(Rollout, id)

  @doc """
  Gets a rollout by ID, raises if not found.
  """
  def get_rollout!(id), do: Repo.get!(Rollout, id)

  @doc """
  Gets a rollout with steps and node_bundle_statuses preloaded.
  """
  def get_rollout_with_details(id) do
    Rollout
    |> Repo.get(id)
    |> Repo.preload(steps: from(s in RolloutStep, order_by: s.step_index))
    |> Repo.preload(:node_bundle_statuses)
  end

  @doc """
  Enqueues a tick job for the given rollout.
  Call this after plan_rollout or resume_rollout to start/continue processing.
  """
  def schedule_tick(rollout_id) do
    enqueue_tick(rollout_id)
  end

  ## Approval Workflow

  @doc """
  Checks if a rollout requires approval based on its project settings.
  """
  def requires_approval?(%Rollout{} = rollout) do
    project = Projects.get_project!(rollout.project_id)
    Projects.Project.approval_required?(project)
  end

  @doc """
  Submits a rollout for approval. If the project requires approval,
  transitions to pending_approval. Otherwise, transitions to approved.
  """
  def submit_for_approval(%Rollout{state: "pending", approval_state: "not_required"} = rollout) do
    project = Projects.get_project!(rollout.project_id)

    if Projects.Project.approval_required?(project) do
      rollout
      |> Rollout.approval_changeset("pending_approval")
      |> Repo.update()
    else
      rollout
      |> Rollout.approval_changeset("approved")
      |> Repo.update()
    end
  end

  def submit_for_approval(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Adds a user's approval to a rollout. Auto-transitions to approved when
  the required number of approvals is reached.

  Returns error if:
  - User is the rollout creator (self-approval not allowed)
  - User doesn't have operator/admin role in the org
  - User has already approved this rollout
  - Rollout is not in pending_approval state
  """
  def approve_rollout(%Rollout{approval_state: "pending_approval"} = rollout, user) do
    project = Projects.get_project!(rollout.project_id)

    with :ok <- validate_not_creator(rollout, user),
         :ok <- validate_approver_role(project, user),
         :ok <- validate_not_already_approved(rollout, user) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _approval} =
        %RolloutApproval{}
        |> RolloutApproval.changeset(%{
          rollout_id: rollout.id,
          user_id: user.id,
          approved_at: now
        })
        |> Repo.insert()

      # Check if we have enough approvals
      approval_count = count_approvals(rollout.id)
      needed = Projects.Project.approvals_needed(project)

      result =
        if approval_count >= needed do
          rollout
          |> Rollout.approval_changeset("approved")
          |> Repo.update()
        else
          {:ok, Repo.get!(Rollout, rollout.id)}
        end

      # Send notification
      maybe_send_notification(fn -> Notifications.notify_rollout_approved(rollout, user) end)

      result
    end
  end

  def approve_rollout(%Rollout{}, _user), do: {:error, :invalid_state}

  @doc """
  Rejects a rollout with a required comment.

  Returns error if:
  - Comment is empty
  - User doesn't have operator/admin role in the org
  - Rollout is not in pending_approval state
  """
  def reject_rollout(%Rollout{approval_state: "pending_approval"} = rollout, user, comment) do
    if is_nil(comment) or String.trim(comment) == "" do
      {:error, :comment_required}
    else
      project = Projects.get_project!(rollout.project_id)

      with :ok <- validate_approver_role(project, user) do
        result =
          rollout
          |> Rollout.approval_changeset("rejected",
            comment: comment,
            rejected_by_id: user.id
          )
          |> Repo.update()

        # Send notification
        maybe_send_notification(fn ->
          Notifications.notify_rollout_rejected(rollout, user, comment)
        end)

        result
      end
    end
  end

  def reject_rollout(%Rollout{}, _user, _comment), do: {:error, :invalid_state}

  @doc """
  Checks if a rollout can be started (planned).
  Returns true if approval_state is approved or not_required.
  """
  def can_start_rollout?(%Rollout{approval_state: approval_state}) do
    approval_state in ~w(approved not_required)
  end

  @doc """
  Lists all approvals for a rollout with preloaded users.
  """
  def list_approvals(rollout_id) do
    from(a in RolloutApproval,
      where: a.rollout_id == ^rollout_id,
      preload: [:user],
      order_by: [asc: a.approved_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all rollouts pending approval, with project and bundle preloaded.
  Can optionally filter by org_id.
  """
  def list_pending_approvals(opts \\ []) do
    query =
      from(r in Rollout,
        where: r.approval_state == "pending_approval",
        where: r.state == "pending",
        preload: [:project, :bundle],
        order_by: [asc: r.inserted_at]
      )

    query =
      case opts[:org_id] do
        nil ->
          query

        org_id ->
          from(r in query,
            join: p in assoc(r, :project),
            where: p.org_id == ^org_id
          )
      end

    Repo.all(query)
  end

  @doc """
  Lists all scheduled rollouts (pending with scheduled_at in the future).
  Returns rollouts with project and bundle preloaded, ordered by scheduled_at.
  """
  def list_scheduled_rollouts(opts \\ []) do
    now = DateTime.utc_now()

    query =
      from(r in Rollout,
        where: r.state == "pending",
        where: not is_nil(r.scheduled_at),
        where: r.scheduled_at > ^now,
        preload: [:project, :bundle],
        order_by: [asc: r.scheduled_at]
      )

    query =
      case opts[:org_id] do
        nil ->
          query

        org_id ->
          from(r in query,
            join: p in assoc(r, :project),
            where: p.org_id == ^org_id
          )
      end

    Repo.all(query)
  end

  @doc """
  Counts the number of approvals for a rollout.
  """
  def count_approvals(rollout_id) do
    from(a in RolloutApproval, where: a.rollout_id == ^rollout_id)
    |> Repo.aggregate(:count)
  end

  defp validate_not_creator(%Rollout{created_by_id: created_by_id}, %{id: user_id})
       when created_by_id == user_id do
    {:error, :self_approval}
  end

  defp validate_not_creator(_rollout, _user), do: :ok

  defp validate_approver_role(project, user) do
    if Orgs.user_has_role?(project.org_id, user.id, "operator") do
      :ok
    else
      {:error, :not_authorized}
    end
  end

  defp validate_not_already_approved(rollout, user) do
    exists =
      from(a in RolloutApproval,
        where: a.rollout_id == ^rollout.id and a.user_id == ^user.id
      )
      |> Repo.exists?()

    if exists do
      {:error, :already_approved}
    else
      :ok
    end
  end

  ## Rollout Lifecycle

  @doc """
  Plans a rollout: resolves target nodes, creates batched steps and
  NodeBundleStatus records, and transitions to running.

  The caller should call `schedule_tick/1` after to begin processing.

  Returns error if rollout requires approval but hasn't been approved.
  """
  def plan_rollout(%Rollout{state: "pending"} = rollout) do
    unless can_start_rollout?(rollout) do
      {:error, :approval_required}
    else
      do_plan_rollout(rollout)
    end
  end

  def plan_rollout(%Rollout{}), do: {:error, :invalid_state}

  defp do_plan_rollout(rollout) do
    node_ids = resolve_target_nodes(rollout.project_id, rollout.target_selector)

    # Filter out pinned nodes if bundle doesn't match
    node_ids = filter_pinned_nodes(node_ids, rollout.bundle_id)

    if node_ids == [] do
      {:error, :no_target_nodes}
    else
      batches =
        cond do
          rollout.strategy == "canary" ->
            plan_canary_batches(node_ids, rollout.canary_analysis_config)

          rollout.strategy == "blue_green" ->
            plan_blue_green_batches(node_ids, rollout.blue_green_config)

          true ->
            chunk_into_batches(
              node_ids,
              rollout.strategy,
              rollout.batch_size,
              rollout.batch_percentage
            )
        end

      result =
        Repo.transaction(fn ->
          # Create steps
          steps =
            batches
            |> Enum.with_index()
            |> Enum.map(fn {batch, index} ->
              # Support both plain [node_ids] and {node_ids, slot, weight} tuples
              {batch_node_ids, slot, weight} =
                case batch do
                  {ids, s, w} -> {ids, s, w}
                  ids when is_list(ids) -> {ids, nil, nil}
                end

              attrs =
                %{
                  rollout_id: rollout.id,
                  step_index: index,
                  node_ids: batch_node_ids,
                  deployment_slot: slot,
                  traffic_weight: weight
                }

              {:ok, step} =
                %RolloutStep{}
                |> RolloutStep.create_changeset(attrs)
                |> Repo.insert()

              step
            end)

          # Create NodeBundleStatus records for all target nodes
          for node_id <- node_ids do
            %NodeBundleStatus{}
            |> NodeBundleStatus.create_changeset(%{
              node_id: node_id,
              rollout_id: rollout.id,
              bundle_id: rollout.bundle_id
            })
            |> Repo.insert!()
          end

          # Set strategy-specific fields
          extra_changes =
            cond do
              rollout.strategy == "canary" ->
                %{canary_step_index: 0}

              rollout.strategy == "blue_green" ->
                %{deployment_slot: "blue"}

              true ->
                %{}
            end

          # Transition to running
          {:ok, updated} =
            rollout
            |> Rollout.state_changeset("running")
            |> Ecto.Changeset.change(extra_changes)
            |> Repo.update()

          # Enqueue first tick
          enqueue_tick(rollout.id)

          {updated, steps}
        end)

      case result do
        {:ok, {updated, _steps}} ->
          broadcast_and_notify(updated, "pending", "running")
          result

        error ->
          error
      end
    end
  end

  defp plan_canary_batches(node_ids, config) do
    steps = (config || %{})["steps"] || [5, 25, 50, 100]
    first_pct = List.first(steps) || 5
    total = length(node_ids)
    canary_size = max(1, ceil(total * first_pct / 100))
    {canary_nodes, remaining_nodes} = Enum.split(node_ids, canary_size)

    if remaining_nodes == [] do
      [canary_nodes]
    else
      [canary_nodes, remaining_nodes]
    end
  end

  defp plan_blue_green_batches(node_ids, config) do
    total = length(node_ids)
    traffic_steps = get_traffic_steps(config)

    if total <= 1 do
      [{node_ids, "green", 100}]
    else
      half = div(total, 2)
      {green_ids, blue_ids} = Enum.split(node_ids, half)

      # Step 0: deploy to green nodes with traffic_weight 0
      deploy_green = {green_ids, "green", 0}

      # Steps 1..N: traffic shift steps on green nodes
      traffic_shift_steps =
        Enum.map(traffic_steps, fn weight -> {green_ids, "green", weight} end)

      # Final step: deploy to blue nodes (catch-up)
      deploy_blue = {blue_ids, "blue", 100}

      [deploy_green] ++ traffic_shift_steps ++ [deploy_blue]
    end
  end

  defp get_traffic_steps(nil), do: [10, 50, 100]
  defp get_traffic_steps(%{"traffic_steps" => steps}) when is_list(steps), do: steps
  defp get_traffic_steps(_), do: [10, 50, 100]

  @doc """
  Core state machine driver. Called by the TickWorker on each tick.
  """
  def tick_rollout(%Rollout{state: "running"} = rollout) do
    rollout = Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

    # Find active step (running, verifying, or validating)
    active_step =
      Enum.find(rollout.steps, fn s -> s.state in ~w(running verifying validating) end)

    cond do
      active_step && active_step.state == "running" ->
        check_step_running(rollout, active_step)

      active_step && active_step.state == "verifying" ->
        check_step_verifying(rollout, active_step)

      active_step && active_step.state == "validating" ->
        check_step_validating(rollout, active_step)

      true ->
        # No active step — start next pending step
        next_step = Enum.find(rollout.steps, fn s -> s.state == "pending" end)

        if next_step do
          start_step(rollout, next_step)
        else
          # All steps completed
          complete_rollout(rollout)
        end
    end
  end

  def tick_rollout(%Rollout{}), do: {:ok, :not_running}

  @doc """
  Pauses a running rollout.
  """
  def pause_rollout(%Rollout{state: "running"} = rollout) do
    case rollout |> Rollout.state_changeset("paused") |> Repo.update() do
      {:ok, updated} ->
        broadcast_and_notify(updated, "running", "paused")
        {:ok, updated}

      error ->
        error
    end
  end

  def pause_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Resumes a paused rollout and reschedules the tick.
  """
  def resume_rollout(%Rollout{state: "paused"} = rollout) do
    case rollout |> Rollout.state_changeset("running") |> Repo.update() do
      {:ok, updated} ->
        enqueue_tick(rollout.id)
        {:ok, updated}

      error ->
        error
    end
  end

  def resume_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Cancels a running, paused, or pending (rejected) rollout.
  """
  def cancel_rollout(%Rollout{state: "pending", approval_state: "rejected"} = rollout) do
    case rollout |> Rollout.state_changeset("cancelled") |> Repo.update() do
      {:ok, updated} ->
        broadcast_and_notify(updated, "pending", "cancelled")
        {:ok, updated}

      error ->
        error
    end
  end

  def cancel_rollout(%Rollout{state: state} = rollout) when state in ~w(running paused) do
    case rollout |> Rollout.state_changeset("cancelled") |> Repo.update() do
      {:ok, updated} ->
        broadcast_and_notify(updated, state, "cancelled")
        {:ok, updated}

      error ->
        error
    end
  end

  def cancel_rollout(%Rollout{}), do: {:error, :invalid_state}

  @doc """
  Cancels the rollout and reverts affected nodes' staged_bundle_id
  back to their active_bundle_id.
  """
  def rollback_rollout(%Rollout{state: state} = rollout) when state in ~w(running paused) do
    result =
      Repo.transaction(fn ->
        # Cancel the rollout
        {:ok, cancelled} =
          rollout
          |> Rollout.state_changeset("cancelled")
          |> Repo.update()

        # Revert staged_bundle_id for affected nodes
        node_ids = get_rollout_node_ids(rollout.id)

        if node_ids != [] do
          from(n in Nodes.Node,
            where: n.id in ^node_ids,
            where: n.staged_bundle_id == ^rollout.bundle_id
          )
          |> Repo.update_all(set: [staged_bundle_id: nil])
        end

        cancelled
      end)

    case result do
      {:ok, cancelled} ->
        broadcast_and_notify(cancelled, state, "cancelled")
        {:ok, cancelled}

      error ->
        error
    end
  end

  def rollback_rollout(%Rollout{}), do: {:error, :invalid_state}

  ## Blue-Green Traffic Controls

  @doc """
  Advances blue-green traffic to the next step.
  Can only be called when the rollout is paused (after validation pause).
  """
  def advance_blue_green_traffic(%Rollout{strategy: "blue_green", state: "paused"} = rollout) do
    case resume_rollout(rollout) do
      {:ok, updated} ->
        log_audit(rollout, "rollout.traffic_advanced")
        {:ok, updated}

      error ->
        error
    end
  end

  def advance_blue_green_traffic(%Rollout{strategy: "blue_green"}),
    do: {:error, :invalid_state}

  def advance_blue_green_traffic(%Rollout{}), do: {:error, :not_blue_green}

  @doc """
  Swaps the active deployment slot for a blue-green rollout.
  Reverts traffic weight to 0 on current active steps and pauses the rollout.
  """
  def swap_blue_green_slot(%Rollout{strategy: "blue_green", state: state} = rollout)
      when state in ~w(running paused) do
    result =
      Repo.transaction(fn ->
        rollout =
          Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

        # Set traffic_weight to 0 on active/verifying/validating steps
        for step <- rollout.steps,
            step.state in ~w(running verifying validating) do
          step
          |> Ecto.Changeset.change(%{traffic_weight: 0})
          |> Repo.update!()
        end

        # Swap deployment slot
        new_slot = if rollout.deployment_slot == "green", do: "blue", else: "green"

        {:ok, updated} =
          rollout
          |> Ecto.Changeset.change(%{deployment_slot: new_slot})
          |> Rollout.state_changeset("paused")
          |> Repo.update()

        updated
      end)

    case result do
      {:ok, updated} ->
        log_audit(updated, "rollout.slot_swapped")
        broadcast_rollout_update(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  def swap_blue_green_slot(%Rollout{strategy: "blue_green"}),
    do: {:error, :invalid_state}

  def swap_blue_green_slot(%Rollout{}), do: {:error, :not_blue_green}

  @doc """
  Instant rollback for blue-green: sets traffic weight to 0 on all active steps,
  cancels the rollout, and clears staged bundles on affected nodes.
  """
  def instant_rollback_blue_green(%Rollout{strategy: "blue_green", state: state} = rollout)
      when state in ~w(running paused) do
    result =
      Repo.transaction(fn ->
        rollout =
          Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

        # Set traffic weight to 0 on all non-completed steps
        for step <- rollout.steps,
            step.state not in ~w(completed failed) do
          step
          |> Ecto.Changeset.change(%{traffic_weight: 0})
          |> Repo.update!()
        end

        # Cancel the rollout
        {:ok, cancelled} =
          rollout
          |> Rollout.state_changeset("cancelled")
          |> Repo.update()

        # Clear staged_bundle_id on affected nodes
        node_ids = get_rollout_node_ids(rollout.id)

        if node_ids != [] do
          from(n in Nodes.Node,
            where: n.id in ^node_ids,
            where: n.staged_bundle_id == ^rollout.bundle_id
          )
          |> Repo.update_all(set: [staged_bundle_id: nil])
        end

        cancelled
      end)

    case result do
      {:ok, cancelled} ->
        log_audit(cancelled, "rollout.instant_rollback")
        broadcast_and_notify(cancelled, state, "cancelled")
        {:ok, cancelled}

      error ->
        error
    end
  end

  def instant_rollback_blue_green(%Rollout{strategy: "blue_green"}),
    do: {:error, :invalid_state}

  def instant_rollback_blue_green(%Rollout{}), do: {:error, :not_blue_green}

  defp log_audit(rollout, action) do
    unless Application.get_env(:sentinel_cp, :env) == :test do
      SentinelCp.Audit.log_system_action(action, "rollout", rollout.id,
        project_id: rollout.project_id,
        changes: %{state: rollout.state, deployment_slot: rollout.deployment_slot}
      )
    end
  end

  ## Queries

  @doc """
  Returns progress counts for a rollout.
  """
  def get_rollout_progress(rollout_id) do
    statuses =
      from(nbs in NodeBundleStatus,
        where: nbs.rollout_id == ^rollout_id,
        group_by: nbs.state,
        select: {nbs.state, count(nbs.id)}
      )
      |> Repo.all()
      |> Map.new()

    total = Enum.reduce(statuses, 0, fn {_state, count}, acc -> acc + count end)
    active = Map.get(statuses, "active", 0)
    failed = Map.get(statuses, "failed", 0)
    pending = total - active - failed

    %{total: total, pending: pending, active: active, failed: failed}
  end

  @doc """
  Resolves target nodes based on selector type.
  """
  def resolve_target_nodes(project_id, %{"type" => "all"}) do
    from(n in Nodes.Node, where: n.project_id == ^project_id, select: n.id)
    |> Repo.all()
  end

  def resolve_target_nodes(project_id, %{"type" => "labels", "labels" => labels}) do
    query = from(n in Nodes.Node, where: n.project_id == ^project_id, select: n.id)

    query =
      Enum.reduce(labels, query, fn {key, value}, q ->
        where(q, [n], fragment("json_extract(?, ?) = ?", n.labels, ^"$.#{key}", ^value))
      end)

    Repo.all(query)
  end

  def resolve_target_nodes(_project_id, %{"type" => "node_ids", "node_ids" => node_ids}) do
    node_ids
  end

  def resolve_target_nodes(_project_id, %{"type" => "groups", "group_ids" => group_ids}) do
    Nodes.get_nodes_by_groups(group_ids) |> Enum.map(& &1.id)
  end

  def resolve_target_nodes(_project_id, _selector), do: []

  defp filter_pinned_nodes(node_ids, bundle_id) do
    # Get nodes that are pinned to a different bundle
    pinned_to_other =
      from(n in Nodes.Node,
        where: n.id in ^node_ids,
        where: not is_nil(n.pinned_bundle_id),
        where: n.pinned_bundle_id != ^bundle_id,
        select: n.id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.reject(node_ids, &MapSet.member?(pinned_to_other, &1))
  end

  ## Private — Tick Logic

  defp traffic_shift_step?(rollout, step) do
    rollout.strategy == "blue_green" &&
      step.deployment_slot == "green" &&
      step.step_index > 0 &&
      step.step_index <= length(get_traffic_steps(rollout.blue_green_config))
  end

  defp start_step(rollout, step) do
    if traffic_shift_step?(rollout, step) do
      start_traffic_shift_step(rollout, step)
    else
      start_deploy_step(rollout, step)
    end
  end

  defp start_traffic_shift_step(rollout, step) do
    # Traffic shift steps skip bundle assignment — bundle already deployed to green nodes
    # Transition directly to verifying (no waiting for node activation)
    {:ok, _step} =
      step
      |> RolloutStep.state_changeset("running")
      |> Repo.update()

    broadcast_rollout_update(rollout)
    {:ok, :step_started}
  end

  defp start_deploy_step(rollout, step) do
    # Re-validate bundle is still compiled (could have been revoked since rollout creation)
    bundle = Bundles.get_bundle!(rollout.bundle_id)

    if bundle.status != "compiled" do
      old_state = rollout.state

      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("failed",
          error: %{"reason" => "bundle_revoked", "bundle_id" => rollout.bundle_id}
        )
        |> Repo.update()

      {:ok, failed_rollout} =
        rollout
        |> Rollout.state_changeset("failed",
          error: %{"reason" => "bundle_revoked", "bundle_id" => rollout.bundle_id}
        )
        |> Repo.update()

      broadcast_and_notify(failed_rollout, old_state, "failed")
      {:ok, :bundle_revoked}
    else
      # Transition step to running
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("running")
        |> Repo.update()

      # Assign bundle to step's nodes
      {:ok, _count} = Bundles.assign_bundle_to_nodes(bundle, step.node_ids)

      # Update NodeBundleStatus records to staging
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(nbs in NodeBundleStatus,
        where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
      )
      |> Repo.update_all(set: [state: "staging", last_report_at: now])

      broadcast_rollout_update(rollout)
      {:ok, :step_started}
    end
  end

  defp check_step_running(rollout, step) do
    # Traffic shift steps skip bundle activation check — transition to verifying immediately
    if traffic_shift_step?(rollout, step) do
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("verifying")
        |> Repo.update()

      broadcast_rollout_update(rollout)
      {:ok, :step_verifying}
    else
      check_step_running_deploy(rollout, step)
    end
  end

  defp check_step_running_deploy(rollout, step) do
    total = length(step.node_ids)

    # Check if all nodes in this step have active_bundle_id == bundle_id
    activated_count =
      from(n in Nodes.Node,
        where: n.id in ^step.node_ids and n.active_bundle_id == ^rollout.bundle_id
      )
      |> Repo.aggregate(:count)

    # Check max_unavailable: count nodes that are offline or have failed
    unavailable_count = count_unavailable_nodes(step.node_ids)

    # With max_unavailable, the step can progress when all available nodes
    # have activated, tolerating up to max_unavailable offline nodes.
    required =
      if rollout.max_unavailable > 0 do
        max(total - rollout.max_unavailable, 0)
      else
        total
      end

    cond do
      rollout.max_unavailable > 0 and unavailable_count > rollout.max_unavailable ->
        # Too many unavailable nodes — pause the rollout
        {:ok, paused_rollout} =
          rollout
          |> Rollout.state_changeset("paused",
            error: %{
              "reason" => "max_unavailable_exceeded",
              "unavailable" => unavailable_count,
              "max_unavailable" => rollout.max_unavailable
            }
          )
          |> Repo.update()

        broadcast_and_notify(paused_rollout, "running", "paused")
        {:ok, :max_unavailable_exceeded}

      activated_count >= required and activated_count > 0 ->
        # Enough nodes activated — transition to verifying
        {:ok, _step} =
          step
          |> RolloutStep.state_changeset("verifying")
          |> Repo.update()

        # Update node bundle statuses
        from(nbs in NodeBundleStatus,
          where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
        )
        |> Repo.update_all(
          set: [
            state: "activating",
            last_report_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )

        broadcast_rollout_update(rollout)
        {:ok, :step_verifying}

      true ->
        # Check deadline
        check_step_deadline(rollout, step)
    end
  end

  defp check_step_verifying(rollout, step) do
    # Check health gates (only for available nodes when max_unavailable is set)
    node_ids = available_node_ids(rollout, step)
    gates_pass = check_health_gates(rollout, step, node_ids)

    cond do
      gates_pass && rollout.strategy == "canary" ->
        clear_health_gate_failure(step)
        check_canary_analysis(rollout, step)

      gates_pass && traffic_shift_step?(rollout, step) ->
        # Blue-green traffic shift steps enter validating state
        clear_health_gate_failure(step)

        {:ok, _step} =
          step
          |> RolloutStep.state_changeset("validating")
          |> Repo.update()

        broadcast_rollout_update(rollout)
        {:ok, :step_validating}

      gates_pass ->
        clear_health_gate_failure(step)
        complete_step(rollout, step)

      rollout.auto_rollback && sustained_failure?(rollout, step) ->
        trigger_auto_rollback(rollout, step)
        {:ok, :auto_rollback_triggered}

      true ->
        track_health_gate_failure(step)
        check_step_deadline(rollout, step)
    end
  end

  defp check_step_validating(rollout, step) do
    node_ids = available_node_ids(rollout, step)
    gates_pass = check_health_gates(rollout, step, node_ids)

    config = rollout.blue_green_config || %{}
    auto_advance = config["auto_advance"] == true
    advance_delay = config["advance_delay_seconds"] || 60
    validation_period = rollout.validation_period_seconds || 300

    wait_seconds = max(validation_period, advance_delay)
    elapsed = DateTime.diff(DateTime.utc_now(), step.validated_at, :second)

    cond do
      !gates_pass && rollout.auto_rollback && sustained_failure?(rollout, step) ->
        trigger_auto_rollback(rollout, step)
        {:ok, :auto_rollback_triggered}

      !gates_pass ->
        track_health_gate_failure(step)
        check_step_deadline(rollout, step)

      elapsed < wait_seconds ->
        clear_health_gate_failure(step)
        {:ok, :validating}

      auto_advance ->
        clear_health_gate_failure(step)
        complete_step(rollout, step)

      true ->
        # auto_advance is false — pause rollout for operator to advance
        clear_health_gate_failure(step)

        {:ok, paused_rollout} =
          rollout
          |> Rollout.state_changeset("paused")
          |> Repo.update()

        broadcast_and_notify(paused_rollout, "running", "paused")
        {:ok, :paused_for_validation}
    end
  end

  defp track_health_gate_failure(step) do
    if is_nil(step.health_gate_failure_since) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      step
      |> Ecto.Changeset.change(%{health_gate_failure_since: now})
      |> Repo.update()
    end

    :ok
  end

  defp clear_health_gate_failure(step) do
    if step.health_gate_failure_since != nil do
      step
      |> Ecto.Changeset.change(%{health_gate_failure_since: nil})
      |> Repo.update()
    end

    :ok
  end

  defp sustained_failure?(_rollout, step) do
    case step.health_gate_failure_since do
      nil -> false
      since -> DateTime.diff(DateTime.utc_now(), since, :second) > 50
    end
  end

  defp complete_step(rollout, step) do
    {:ok, _step} =
      step
      |> RolloutStep.state_changeset("completed")
      |> Repo.update()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(nbs in NodeBundleStatus,
      where: nbs.rollout_id == ^rollout.id and nbs.node_id in ^step.node_ids
    )
    |> Repo.update_all(
      set: [state: "active", activated_at: now, verified_at: now, last_report_at: now]
    )

    # Set expected_bundle_id for nodes that completed this step
    SentinelCp.Nodes.set_expected_bundle_for_nodes(step.node_ids, rollout.bundle_id)

    # Track active deployment slot and traffic step index for blue-green rollouts
    if rollout.strategy == "blue_green" do
      changes =
        if traffic_shift_step?(rollout, step) do
          %{traffic_step_index: (rollout.traffic_step_index || 0) + 1}
        else
          %{}
        end

      # Set deployment_slot to green when final traffic step (100%) completes
      changes =
        if step.deployment_slot == "green" && step.traffic_weight == 100 do
          Map.put(changes, :deployment_slot, "green")
        else
          changes
        end

      if map_size(changes) > 0 do
        rollout
        |> Ecto.Changeset.change(changes)
        |> Repo.update()
      end
    end

    broadcast_rollout_update(rollout)
    {:ok, :step_completed}
  end

  defp check_canary_analysis(rollout, step) do
    # Determine canary vs baseline node IDs
    rollout_with_steps =
      Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

    canary_node_ids =
      rollout_with_steps.steps
      |> Enum.filter(&(&1.state in ~w(completed running verifying)))
      |> Enum.flat_map(& &1.node_ids)

    baseline_node_ids =
      rollout_with_steps.steps
      |> Enum.filter(&(&1.state == "pending"))
      |> Enum.flat_map(& &1.node_ids)

    {decision, result} = CanaryAnalysis.analyze(rollout, canary_node_ids, baseline_node_ids)
    store_canary_result(rollout, result)

    case decision do
      :promote ->
        # Complete current step
        complete_step(rollout, step)

        if CanaryAnalysis.next_step?(rollout.canary_analysis_config, rollout.canary_step_index) do
          # Increment canary step index and recalculate next batch
          new_index = rollout.canary_step_index + 1

          next_pct =
            CanaryAnalysis.current_step_percentage(rollout.canary_analysis_config, new_index)

          {:ok, _updated} =
            rollout
            |> Rollout.canary_changeset(%{canary_step_index: new_index})
            |> Repo.update()

          # Redistribute remaining nodes based on new percentage
          redistribute_canary_steps(rollout, new_index, next_pct)

          {:ok, :canary_promoted}
        else
          # Final step — rollout will complete via normal tick cycle
          {:ok, :canary_final_promote}
        end

      :rollback ->
        rollback_rollout(rollout)
        {:ok, :canary_rollback}

      :extend ->
        # Not enough data — wait for next tick
        {:ok, :canary_extend}
    end
  end

  defp redistribute_canary_steps(rollout, _new_index, next_pct) do
    # Get remaining pending step node IDs
    rollout_with_steps =
      Repo.preload(rollout, steps: from(s in RolloutStep, order_by: s.step_index))

    pending_steps = Enum.filter(rollout_with_steps.steps, &(&1.state == "pending"))
    remaining_node_ids = Enum.flat_map(pending_steps, & &1.node_ids)

    if remaining_node_ids != [] do
      total_original = length(get_rollout_node_ids(rollout.id))
      next_batch_size = max(1, ceil(total_original * next_pct / 100))
      # Cap at the number of remaining nodes
      next_batch_size = min(next_batch_size, length(remaining_node_ids))
      {next_batch, rest} = Enum.split(remaining_node_ids, next_batch_size)

      # Delete existing pending steps and create new ones
      for pending_step <- pending_steps do
        Repo.delete(pending_step)
      end

      max_step_index =
        rollout_with_steps.steps
        |> Enum.map(& &1.step_index)
        |> Enum.max(fn -> -1 end)

      # Create next canary batch step
      {:ok, _step} =
        %RolloutStep{}
        |> RolloutStep.create_changeset(%{
          rollout_id: rollout.id,
          step_index: max_step_index + 1,
          node_ids: next_batch
        })
        |> Repo.insert()

      # Create remaining nodes step if any left
      if rest != [] do
        {:ok, _step} =
          %RolloutStep{}
          |> RolloutStep.create_changeset(%{
            rollout_id: rollout.id,
            step_index: max_step_index + 2,
            node_ids: rest
          })
          |> Repo.insert()
      end
    end
  end

  defp store_canary_result(rollout, result) do
    existing = rollout.canary_analysis_results || %{"analyses" => []}
    analyses = (existing["analyses"] || []) ++ [stringify_result(result)]

    {:ok, _} =
      rollout
      |> Rollout.canary_changeset(%{canary_analysis_results: %{"analyses" => analyses}})
      |> Repo.update()
  end

  defp stringify_result(result) do
    result
    |> Map.new(fn {k, v} ->
      key = to_string(k)

      val =
        case v do
          %DateTime{} -> DateTime.to_iso8601(v)
          %{} = m -> Map.new(m, fn {mk, mv} -> {to_string(mk), mv} end)
          other -> other
        end

      {key, val}
    end)
  end

  defp check_health_gates(rollout, _step, check_node_ids) do
    gates = rollout.health_gates || %{}

    # All enabled gates must pass for available nodes
    standard_gates_pass =
      check_heartbeat_gate(gates, check_node_ids) and
        check_error_rate_gate(gates, check_node_ids) and
        check_latency_gate(gates, check_node_ids) and
        check_cpu_gate(gates, check_node_ids) and
        check_memory_gate(gates, check_node_ids)

    # Also check custom health check endpoints
    custom_gates_pass =
      if rollout.custom_health_checks && rollout.custom_health_checks != [] do
        check_custom_health_endpoints(rollout.custom_health_checks)
      else
        true
      end

    standard_gates_pass and custom_gates_pass
  end

  defp check_custom_health_endpoints(endpoint_ids) do
    endpoints =
      from(e in HealthCheckEndpoint,
        where: e.id in ^endpoint_ids,
        where: e.enabled == true
      )
      |> Repo.all()

    case HealthChecker.check_all(endpoints) do
      {:ok, results} -> HealthChecker.all_passed?(results)
      _ -> false
    end
  end

  defp check_heartbeat_gate(gates, node_ids) do
    if Map.get(gates, "heartbeat_healthy", false) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        latest != nil && get_in(latest.health, ["status"]) == "healthy"
      end)
    else
      true
    end
  end

  defp check_error_rate_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_error_rate")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        error_rate = get_in(latest || %{}, [Access.key(:metrics, %{}), "error_rate"]) || 0.0
        error_rate <= threshold
      end)
    else
      true
    end
  end

  defp check_latency_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_latency_ms")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        latency = get_in(latest || %{}, [Access.key(:metrics, %{}), "latency_p99_ms"]) || 0.0
        latency <= threshold
      end)
    else
      true
    end
  end

  defp check_cpu_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_cpu_percent")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        cpu = get_in(latest || %{}, [Access.key(:metrics, %{}), "cpu_percent"]) || 0.0
        cpu <= threshold
      end)
    else
      true
    end
  end

  defp check_memory_gate(gates, node_ids) do
    threshold = Map.get(gates, "max_memory_percent")

    if is_number(threshold) do
      Enum.all?(node_ids, fn node_id ->
        latest = latest_heartbeat(node_id)
        mem = get_in(latest || %{}, [Access.key(:metrics, %{}), "memory_percent"]) || 0.0
        mem <= threshold
      end)
    else
      true
    end
  end

  defp latest_heartbeat(node_id) do
    from(h in Nodes.NodeHeartbeat,
      where: h.node_id == ^node_id,
      order_by: [desc: h.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp check_step_deadline(rollout, step) do
    deadline = rollout.progress_deadline_seconds
    elapsed = DateTime.diff(DateTime.utc_now(), step.started_at, :second)

    if elapsed > deadline do
      old_state = rollout.state

      # Step failed — deadline exceeded
      {:ok, _step} =
        step
        |> RolloutStep.state_changeset("failed",
          error: %{"reason" => "deadline_exceeded", "elapsed_seconds" => elapsed}
        )
        |> Repo.update()

      # Fail the rollout
      {:ok, failed_rollout} =
        rollout
        |> Rollout.state_changeset("failed",
          error: %{
            "reason" => "step_deadline_exceeded",
            "step_index" => step.step_index,
            "elapsed_seconds" => elapsed
          }
        )
        |> Repo.update()

      broadcast_and_notify(failed_rollout, old_state, "failed")

      # Trigger auto-rollback if enabled
      if rollout.auto_rollback do
        trigger_auto_rollback(rollout, step)
      end

      {:ok, :deadline_exceeded}
    else
      {:ok, :waiting}
    end
  end

  defp trigger_auto_rollback(rollout, failed_step) do
    require Logger

    case rollout.strategy do
      "blue_green" ->
        # Use instant rollback for blue-green — reverts traffic and cancels
        case instant_rollback_blue_green(rollout) do
          {:ok, _} ->
            Logger.info("Auto-rollback (blue-green instant) triggered",
              rollout_id: rollout.id
            )

          {:error, reason} ->
            Logger.warning("Auto-rollback (blue-green) failed",
              rollout_id: rollout.id,
              reason: inspect(reason)
            )
        end

      "canary" ->
        rollback_rollout(rollout)

      _ ->
        trigger_auto_rollback_generic(rollout, failed_step)
    end
  end

  defp trigger_auto_rollback_generic(rollout, failed_step) do
    require Logger

    # Get the previous bundle that was running on the affected nodes
    node_ids = failed_step.node_ids

    # Find the most common previous bundle among affected nodes
    previous_bundles =
      from(n in Nodes.Node,
        where: n.id in ^node_ids,
        where: not is_nil(n.active_bundle_id),
        where: n.active_bundle_id != ^rollout.bundle_id,
        group_by: n.active_bundle_id,
        select: {n.active_bundle_id, count(n.id)},
        order_by: [desc: count(n.id)]
      )
      |> Repo.all()

    case previous_bundles do
      [{previous_bundle_id, _count} | _] ->
        # Create a rollback rollout
        attrs = %{
          project_id: rollout.project_id,
          bundle_id: previous_bundle_id,
          target_selector: %{"type" => "node_ids", "node_ids" => node_ids},
          strategy: "all_at_once",
          created_by_id: rollout.created_by_id
        }

        case create_rollout(attrs) do
          {:ok, rollback_rollout} ->
            Logger.info("Auto-rollback initiated",
              failed_rollout_id: rollout.id,
              rollback_rollout_id: rollback_rollout.id,
              bundle_id: previous_bundle_id
            )

            plan_rollout(rollback_rollout)

          {:error, reason} ->
            Logger.warning("Auto-rollback failed to create rollout",
              failed_rollout_id: rollout.id,
              reason: inspect(reason)
            )
        end

      [] ->
        Logger.info("Auto-rollback skipped: no previous bundle found", rollout_id: rollout.id)
    end
  end

  defp complete_rollout(rollout) do
    old_state = rollout.state

    {:ok, updated} =
      rollout
      |> Rollout.state_changeset("completed")
      |> Repo.update()

    # Auto-resolve drift events for nodes in this rollout
    resolve_drift_events_for_rollout(rollout)

    broadcast_and_notify(updated, old_state, "completed")
    {:ok, updated}
  end

  defp resolve_drift_events_for_rollout(rollout) do
    node_ids = get_rollout_node_ids(rollout.id)

    for node_id <- node_ids do
      case Nodes.get_active_drift_event(node_id) do
        nil ->
          :ok

        event ->
          # Only resolve if the drift was for the bundle we just rolled out
          if event.expected_bundle_id == rollout.bundle_id do
            Nodes.resolve_drift_event(event, "rollout_completed")
          end
      end
    end
  end

  ## Private — Helpers

  defp validate_bundle_compiled(changeset) do
    bundle_id = Ecto.Changeset.get_field(changeset, :bundle_id)

    if bundle_id do
      case Bundles.get_bundle(bundle_id) do
        %{status: "compiled"} -> {:ok, changeset}
        %{} -> {:error, :bundle_not_compiled}
        nil -> {:error, :bundle_not_found}
      end
    else
      {:ok, changeset}
    end
  end

  defp chunk_into_batches(node_ids, "all_at_once", _batch_size, _batch_pct) do
    [node_ids]
  end

  defp chunk_into_batches(node_ids, _strategy, _batch_size, batch_percentage)
       when is_integer(batch_percentage) and batch_percentage > 0 do
    total = length(node_ids)
    batch_size = max(1, div(total * batch_percentage, 100))
    Enum.chunk_every(node_ids, batch_size)
  end

  defp chunk_into_batches(node_ids, _strategy, batch_size, _batch_pct) do
    Enum.chunk_every(node_ids, batch_size)
  end

  defp count_unavailable_nodes(node_ids) do
    from(n in Nodes.Node,
      where: n.id in ^node_ids and n.status in ~w(offline unknown)
    )
    |> Repo.aggregate(:count)
  end

  defp available_node_ids(rollout, step) do
    if rollout.max_unavailable > 0 do
      unavailable =
        from(n in Nodes.Node,
          where: n.id in ^step.node_ids and n.status in ~w(offline unknown),
          select: n.id
        )
        |> Repo.all()
        |> MapSet.new()

      Enum.reject(step.node_ids, &MapSet.member?(unavailable, &1))
    else
      step.node_ids
    end
  end

  defp get_rollout_node_ids(rollout_id) do
    from(nbs in NodeBundleStatus,
      where: nbs.rollout_id == ^rollout_id,
      select: nbs.node_id
    )
    |> Repo.all()
  end

  defp enqueue_tick(rollout_id) do
    # Skip in Oban inline/testing mode to prevent immediate execution
    # during tests — tests call tick_rollout directly
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{rollout_id: rollout_id}
      |> TickWorker.new(schedule_in: 1)
      |> Oban.insert()
    end
  end

  defp broadcast_rollout_update(rollout) do
    Phoenix.PubSub.broadcast(
      SentinelCp.PubSub,
      "rollout:#{rollout.id}",
      {:rollout_updated, rollout.id}
    )

    Phoenix.PubSub.broadcast(
      SentinelCp.PubSub,
      "rollouts:#{rollout.project_id}",
      {:rollout_updated, rollout.id}
    )

    Absinthe.Subscription.publish(SentinelCpWeb.Endpoint, rollout, rollout_progress: rollout.id)
  end

  defp broadcast_and_notify(rollout, old_state, new_state) do
    broadcast_rollout_update(rollout)

    maybe_send_notification(fn ->
      Notifications.notify_rollout_state_change(rollout, old_state, new_state)
    end)
  end

  defp maybe_send_notification(fun) do
    # Skip notifications in test mode to avoid sandbox issues
    unless Application.get_env(:sentinel_cp, :env) == :test do
      Task.start(fun)
    end
  end
end
