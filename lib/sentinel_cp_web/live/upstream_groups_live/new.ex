defmodule SentinelCpWeb.UpstreamGroupsLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @algorithms ~w(round_robin least_conn ip_hash consistent_hash weighted random)

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        trust_stores = Services.list_trust_stores(project.id)

        {:ok,
         assign(socket,
           page_title: "New Upstream Group — #{project.name}",
           org: org,
           project: project,
           algorithms: @algorithms,
           trust_stores: trust_stores,
           show_circuit_breaker: false
         )}
    end
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    key = String.to_existing_atom("show_#{section}")
    {:noreply, assign(socket, [{key, !socket.assigns[key]}])}
  end

  @impl true
  def handle_event("create_group", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      algorithm: params["algorithm"] || "round_robin",
      trust_store_id: blank_to_nil(params["trust_store_id"])
    }

    attrs = maybe_put_circuit_breaker(attrs, params)

    case Services.create_upstream_group(attrs) do
      {:ok, group} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "upstream_group", group.id,
          project_id: project.id
        )

        show_path = group_show_path(socket.assigns.org, project, group)

        {:noreply,
         socket
         |> put_flash(:info, "Upstream group created.")
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
      <h1 class="text-xl font-bold">Create Upstream Group</h1>

      <.k8s_section>
        <form phx-submit="create_group" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input type="text" name="name" required class="input input-bordered input-sm w-full" placeholder="e.g. API Backends" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea name="description" rows="2" class="textarea textarea-bordered textarea-sm w-full" placeholder="Optional description"></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Algorithm</span></label>
            <select name="algorithm" class="select select-bordered select-sm w-48">
              <option :for={alg <- @algorithms} value={alg}>{alg}</option>
            </select>
          </div>

          <div :if={@trust_stores != []} class="form-control">
            <label class="label"><span class="label-text font-medium">Trust Store (optional)</span></label>
            <select name="trust_store_id" class="select select-bordered select-sm w-full">
              <option value="">None</option>
              <option :for={ts <- @trust_stores} value={ts.id}>{ts.name}</option>
            </select>
            <label class="label">
              <span class="label-text-alt text-base-content/50">CA bundle for verifying upstream TLS connections</span>
            </label>
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
                  class="input input-bordered input-xs w-24"
                  placeholder="1"
                  min="1"
                />
              </div>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Group</button>
            <.link navigate={groups_path(@org, @project)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp groups_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups"

  defp groups_path(nil, project),
    do: ~p"/projects/#{project.slug}/upstream-groups"

  defp group_show_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp group_show_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str

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

        if cleaned == %{}, do: attrs, else: Map.put(attrs, :circuit_breaker, cleaned)

      _ ->
        attrs
    end
  end
end
