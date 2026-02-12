defmodule SentinelCpWeb.UpstreamGroupsLive.Edit do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @algorithms ~w(round_robin least_conn ip_hash consistent_hash weighted random)

  @impl true
  def mount(%{"project_slug" => slug, "id" => group_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         group when not is_nil(group) <- Services.get_upstream_group(group_id),
         true <- group.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Upstream Group #{group.name} — #{project.name}",
         org: org,
         project: project,
         group: group,
         algorithms: @algorithms,
         show_circuit_breaker: group.circuit_breaker != %{} && group.circuit_breaker != nil
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    key = String.to_existing_atom("show_#{section}")
    {:noreply, assign(socket, [{key, !socket.assigns[key]}])}
  end

  @impl true
  def handle_event("update_group", params, socket) do
    group = socket.assigns.group
    project = socket.assigns.project

    attrs = %{
      name: params["name"],
      description: params["description"],
      algorithm: params["algorithm"]
    }

    attrs = maybe_put_circuit_breaker(attrs, params)

    case Services.update_upstream_group(group, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "upstream_group", updated.id,
          project_id: project.id
        )

        show_path = group_show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Upstream group updated.")
         |> push_navigate(to: show_path)}

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
      <h1 class="text-xl font-bold">Edit Upstream Group: {@group.name}</h1>

      <.k8s_section>
        <form phx-submit="update_group" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input type="text" name="name" value={@group.name} required class="input input-bordered input-sm w-full" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea name="description" rows="2" class="textarea textarea-bordered textarea-sm w-full">{@group.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Algorithm</span></label>
            <select name="algorithm" class="select select-bordered select-sm w-48">
              <option :for={alg <- @algorithms} value={alg} selected={alg == @group.algorithm}>{alg}</option>
            </select>
          </div>

          <div class="divider text-xs text-base-content/50">Advanced Settings</div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="circuit_breaker"
              class="btn btn-ghost btn-xs"
            >
              {if @show_circuit_breaker, do: "▼", else: "▶"} Circuit Breaker
            </button>
            <div :if={@show_circuit_breaker} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Failure Threshold</span></label>
                <input
                  type="number"
                  name="circuit_breaker[failure_threshold]"
                  value={@group.circuit_breaker["failure_threshold"]}
                  class="input input-bordered input-xs w-24"
                  placeholder="5"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Success Threshold</span></label>
                <input
                  type="number"
                  name="circuit_breaker[success_threshold]"
                  value={@group.circuit_breaker["success_threshold"]}
                  class="input input-bordered input-xs w-24"
                  placeholder="3"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Timeout (seconds)</span></label>
                <input
                  type="number"
                  name="circuit_breaker[timeout]"
                  value={@group.circuit_breaker["timeout"]}
                  class="input input-bordered input-xs w-24"
                  placeholder="30"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Half-Open Max Requests</span></label>
                <input
                  type="number"
                  name="circuit_breaker[half_open_max_requests]"
                  value={@group.circuit_breaker["half_open_max_requests"]}
                  class="input input-bordered input-xs w-24"
                  placeholder="1"
                  min="1"
                />
              </div>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={group_show_path(@org, @project, @group)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp group_show_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp group_show_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp maybe_put_circuit_breaker(attrs, params) do
    case params["circuit_breaker"] do
      nil ->
        attrs

      %{} = map ->
        cleaned =
          map
          |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end)
          |> Map.new(fn {k, v} ->
            case Integer.parse(v) do
              {n, ""} -> {k, n}
              _ -> {k, v}
            end
          end)

        Map.put(attrs, :circuit_breaker, cleaned)

      _ ->
        attrs
    end
  end
end
