defmodule SentinelCpWeb.GraphQL.Resolvers.Rollouts do
  @moduledoc false
  alias SentinelCp.Audit
  alias SentinelCp.Rollouts

  def list(_parent, %{project_id: project_id}, _resolution) do
    {:ok, Rollouts.list_rollouts(project_id)}
  end

  def list_for_project(project, _args, _resolution) do
    {:ok, Rollouts.list_rollouts(project.id)}
  end

  def create(_parent, %{input: input}, %{context: context}) do
    case Rollouts.create_rollout(input) do
      {:ok, rollout} ->
        audit(context, "create", "rollout", rollout.id, rollout.project_id)
        {:ok, rollout}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  def pause(_parent, %{id: id}, %{context: context}) do
    with_rollout(id, fn rollout ->
      case Rollouts.pause_rollout(rollout) do
        {:ok, updated} ->
          audit(context, "pause", "rollout", id, rollout.project_id)
          {:ok, updated}

        {:error, reason} ->
          {:error, to_string(reason)}
      end
    end)
  end

  def resume(_parent, %{id: id}, %{context: context}) do
    with_rollout(id, fn rollout ->
      case Rollouts.resume_rollout(rollout) do
        {:ok, updated} ->
          audit(context, "resume", "rollout", id, rollout.project_id)
          {:ok, updated}

        {:error, reason} ->
          {:error, to_string(reason)}
      end
    end)
  end

  def resolve_progress(rollout, _args, _resolution) do
    {:ok, Rollouts.get_rollout_progress(rollout.id)}
  end

  defp with_rollout(id, fun) do
    case Rollouts.get_rollout(id) do
      nil -> {:error, "Rollout not found"}
      rollout -> fun.(rollout)
    end
  end

  defp audit(context, action, resource_type, resource_id, project_id) do
    if api_key = context[:current_api_key] do
      Audit.log_api_key_action(api_key, action, resource_type, resource_id,
        project_id: project_id
      )
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
