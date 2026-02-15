defmodule SentinelCpWeb.Api.RolloutController do
  @moduledoc """
  API controller for rollout management.
  """
  use SentinelCpWeb, :controller

  alias SentinelCp.{Rollouts, Projects, Audit}

  @doc """
  POST /api/v1/projects/:project_slug/rollouts
  Creates a new rollout for a compiled bundle.
  """
  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- %{
           project_id: project.id,
           bundle_id: params["bundle_id"],
           target_selector: params["target_selector"] || %{"type" => "all"},
           strategy: params["strategy"] || "rolling",
           batch_size: params["batch_size"] || 1,
           max_unavailable: params["max_unavailable"] || 0,
           progress_deadline_seconds: params["progress_deadline_seconds"] || 600,
           health_gates: params["health_gates"] || %{"heartbeat_healthy" => true},
           created_by_id: conn.assigns[:current_api_key] && conn.assigns.current_api_key.user_id
         },
         {:ok, rollout} <- Rollouts.create_rollout(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.created", "rollout", rollout.id,
        project_id: project.id,
        changes: %{bundle_id: rollout.bundle_id, strategy: rollout.strategy}
      )

      conn
      |> put_status(:created)
      |> json(rollout_to_json(rollout))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :bundle_not_compiled} ->
        conn |> put_status(:conflict) |> json(%{error: "Bundle must be compiled before rollout"})

      {:error, :bundle_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Bundle not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/rollouts
  Lists rollouts for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts =
        []
        |> then(fn opts ->
          if params["state"], do: [{:state, params["state"]} | opts], else: opts
        end)

      rollouts = Rollouts.list_rollouts(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        rollouts: Enum.map(rollouts, &rollout_to_json/1),
        total: length(rollouts)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/rollouts/:id
  Shows rollout details with steps and progress.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id) do
      rollout = Rollouts.get_rollout_with_details(rollout.id)
      progress = Rollouts.get_rollout_progress(rollout.id)

      conn
      |> put_status(:ok)
      |> json(%{
        rollout: rollout_to_json(rollout),
        steps: Enum.map(rollout.steps, &step_to_json/1),
        progress: progress
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/pause
  """
  def pause(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.pause_rollout(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.paused", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout cannot be paused in current state"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/resume
  """
  def resume(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.resume_rollout(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.resumed", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout cannot be resumed in current state"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/cancel
  """
  def cancel(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.cancel_rollout(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.cancelled", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout cannot be cancelled in current state"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/rollback
  """
  def rollback(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.rollback_rollout(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.rolled_back", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout cannot be rolled back in current state"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/swap-slot
  """
  def swap_slot(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.swap_blue_green_slot(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.slot_swapped", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :not_blue_green} ->
        conn |> put_status(:conflict) |> json(%{error: "Not a blue-green rollout"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout cannot swap slot in current state"})
    end
  end

  @doc """
  POST /api/v1/projects/:project_slug/rollouts/:id/advance-traffic
  """
  def advance_traffic(conn, %{"project_slug" => project_slug, "id" => rollout_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, rollout} <- get_rollout(rollout_id, project.id),
         {:ok, updated} <- Rollouts.advance_blue_green_traffic(rollout) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "rollout.traffic_advanced", "rollout", rollout.id,
        project_id: project.id
      )

      conn |> put_status(:ok) |> json(rollout_to_json(updated))
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :rollout_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Rollout not found"})

      {:error, :not_blue_green} ->
        conn |> put_status(:conflict) |> json(%{error: "Not a blue-green rollout"})

      {:error, :invalid_state} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Rollout must be paused to advance traffic"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_rollout(id, project_id) do
    case Rollouts.get_rollout(id) do
      nil -> {:error, :rollout_not_found}
      %{project_id: ^project_id} = rollout -> {:ok, rollout}
      _ -> {:error, :rollout_not_found}
    end
  end

  defp rollout_to_json(rollout) do
    %{
      id: rollout.id,
      project_id: rollout.project_id,
      bundle_id: rollout.bundle_id,
      target_selector: rollout.target_selector,
      strategy: rollout.strategy,
      batch_size: rollout.batch_size,
      max_unavailable: rollout.max_unavailable,
      progress_deadline_seconds: rollout.progress_deadline_seconds,
      health_gates: rollout.health_gates,
      state: rollout.state,
      deployment_slot: rollout.deployment_slot,
      blue_green_config: rollout.blue_green_config,
      traffic_step_index: rollout.traffic_step_index,
      started_at: rollout.started_at,
      completed_at: rollout.completed_at,
      error: rollout.error,
      inserted_at: rollout.inserted_at,
      updated_at: rollout.updated_at
    }
  end

  defp step_to_json(step) do
    %{
      id: step.id,
      step_index: step.step_index,
      node_ids: step.node_ids,
      state: step.state,
      deployment_slot: step.deployment_slot,
      traffic_weight: step.traffic_weight,
      started_at: step.started_at,
      completed_at: step.completed_at,
      error: step.error
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
