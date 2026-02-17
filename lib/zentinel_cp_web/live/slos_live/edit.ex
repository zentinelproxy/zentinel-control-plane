defmodule ZentinelCpWeb.SlosLive.Edit do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Audit, Observability, Projects}
  alias ZentinelCp.Observability.Slo

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         slo when not is_nil(slo) <- Observability.get_slo(id),
         true <- slo.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit #{slo.name} - #{project.name}",
         org: org,
         project: project,
         slo: slo,
         sli_types: Slo.sli_types()
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("update_slo", params, socket) do
    slo = socket.assigns.slo
    project = socket.assigns.project

    attrs = %{
      name: params["name"],
      description: params["description"],
      sli_type: params["sli_type"],
      target: parse_float(params["target"]),
      window_days: parse_int(params["window_days"], slo.window_days)
    }

    case Observability.update_slo(slo, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "update",
          "slo",
          updated.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "SLO updated.")
         |> push_navigate(to: slo_path(socket.assigns.org, project, updated))}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">Edit SLO: {@slo.name}</h1>

      <.k8s_section>
        <form phx-submit="update_slo" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@slo.name}
              required
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              class="textarea textarea-bordered textarea-sm w-full"
              rows="2"
            >{@slo.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">SLI Type</span></label>
            <select name="sli_type" required class="select select-bordered select-sm w-full">
              <option :for={type <- @sli_types} value={type} selected={type == @slo.sli_type}>
                {sli_type_label(type)}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Target</span></label>
            <input
              type="number"
              name="target"
              value={@slo.target}
              required
              step="any"
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Window (days)</span></label>
            <input
              type="number"
              name="window_days"
              value={@slo.window_days}
              min="1"
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={slo_path(@org, @project, @slo)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp sli_type_label("availability"), do: "Availability (%)"
  defp sli_type_label("latency_p99"), do: "Latency P99 (ms)"
  defp sli_type_label("latency_p95"), do: "Latency P95 (ms)"
  defp sli_type_label("error_rate"), do: "Error Rate (%)"
  defp sli_type_label(type), do: type

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(val), do: val

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(val, _default), do: val
end
