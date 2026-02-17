defmodule ZentinelCpWeb.SlosLive.New do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Audit, Observability, Projects}
  alias ZentinelCp.Observability.Slo

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New SLO - #{project.name}",
           org: org,
           project: project,
           sli_types: Slo.sli_types()
         )}
    end
  end

  @impl true
  def handle_event("create_slo", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      sli_type: params["sli_type"],
      target: parse_float(params["target"]),
      window_days: parse_int(params["window_days"], 30)
    }

    case Observability.create_slo(attrs) do
      {:ok, slo} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "create",
          "slo",
          slo.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "SLO created.")
         |> push_navigate(to: slo_path(socket.assigns.org, project, slo))}

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
      <h1 class="text-xl font-bold">New SLO</h1>

      <.k8s_section>
        <form phx-submit="create_slo" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              placeholder="e.g. API Availability"
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              class="textarea textarea-bordered textarea-sm w-full"
              rows="2"
              placeholder="Optional description..."
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">SLI Type</span></label>
            <select name="sli_type" required class="select select-bordered select-sm w-full">
              <option value="">Select type...</option>
              <option :for={type <- @sli_types} value={type}>{sli_type_label(type)}</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Target</span></label>
            <input
              type="number"
              name="target"
              required
              step="any"
              placeholder="e.g. 99.9"
              class="input input-bordered input-sm w-full"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Availability/Error Rate: percentage (e.g. 99.9). Latency: milliseconds (e.g. 200).
              </span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Window (days)</span></label>
            <input
              type="number"
              name="window_days"
              value="30"
              min="1"
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create SLO</button>
            <.link navigate={slos_path(@org, @project)} class="btn btn-ghost btn-sm">
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
