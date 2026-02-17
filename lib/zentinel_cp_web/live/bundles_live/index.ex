defmodule ZentinelCpWeb.BundlesLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Bundles, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "bundles:#{project.id}")
        end

        bundles = Bundles.list_bundles(project.id)
        environments = Projects.list_environments(project.id)
        promotions_map = get_promotions_map(bundles)

        {:ok,
         assign(socket,
           page_title: "Bundles — #{project.name}",
           org: org,
           project: project,
           bundles: bundles,
           environments: environments,
           promotions_map: promotions_map,
           show_upload: false
         )}
    end
  end

  @impl true
  def handle_event("toggle_upload", _, socket) do
    {:noreply, assign(socket, show_upload: !socket.assigns.show_upload)}
  end

  @impl true
  def handle_event(
        "create_bundle",
        %{"version" => version, "config_source" => config_source},
        socket
      ) do
    project = socket.assigns.project

    case Bundles.create_bundle(%{
           project_id: project.id,
           version: version,
           config_source: config_source
         }) do
      {:ok, _bundle} ->
        bundles = Bundles.list_bundles(project.id)

        {:noreply,
         socket
         |> assign(bundles: bundles, show_upload: false)
         |> put_flash(:info, "Bundle created, compilation started.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed to create bundle: #{errors}")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    bundle = Bundles.get_bundle!(id)
    project = socket.assigns.project

    case Bundles.delete_bundle(bundle) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "bundle", bundle.id,
          project_id: project.id
        )

        bundles = Bundles.list_bundles(project.id)

        {:noreply,
         socket
         |> assign(bundles: bundles)
         |> put_flash(:info, "Bundle deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete bundle.")}
    end
  end

  @impl true
  def handle_info({:bundle_compiled, _bundle_id}, socket) do
    bundles = Bundles.list_bundles(socket.assigns.project.id)
    promotions_map = get_promotions_map(bundles)
    {:noreply, assign(socket, bundles: bundles, promotions_map: promotions_map)}
  end

  @impl true
  def handle_info({:bundle_failed, _bundle_id}, socket) do
    bundles = Bundles.list_bundles(socket.assigns.project.id)
    promotions_map = get_promotions_map(bundles)
    {:noreply, assign(socket, bundles: bundles, promotions_map: promotions_map)}
  end

  defp get_promotions_map(bundles) do
    bundle_ids = Enum.map(bundles, & &1.id)

    if bundle_ids == [] do
      %{}
    else
      import Ecto.Query

      ZentinelCp.Bundles.BundlePromotion
      |> where([p], p.bundle_id in ^bundle_ids)
      |> ZentinelCp.Repo.all()
      |> Enum.group_by(& &1.bundle_id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Bundles</h1>
        </:filters>
        <:actions>
          <.link navigate={bundle_diff_path(@org, @project)} class="btn btn-outline btn-sm">
            Compare Bundles
          </.link>
          <.link navigate={bundle_history_path(@org, @project)} class="btn btn-outline btn-sm">
            Version History
          </.link>
          <.link navigate={bundle_new_path(@org, @project)} class="btn btn-primary btn-sm">
            New Bundle
          </.link>
        </:actions>
      </.table_toolbar>

      <div :if={@show_upload}>
        <.k8s_section title="Quick Create Bundle">
          <form phx-submit="create_bundle" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Version</span></label>
              <input
                type="text"
                name="version"
                required
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="e.g. 1.0.0"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">KDL Configuration</span></label>
              <textarea
                name="config_source"
                required
                rows="12"
                class="textarea textarea-bordered textarea-sm font-mono text-sm w-full"
                placeholder="// Paste your zentinel.kdl config here"
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create & Compile</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_upload">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Version</th>
              <th class="text-xs uppercase">Status</th>
              <th :if={@environments != []} class="text-xs uppercase">Environments</th>
              <th class="text-xs uppercase">Size</th>
              <th class="text-xs uppercase">Checksum</th>
              <th class="text-xs uppercase">Created</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={bundle <- @bundles}>
              <td>
                <.link
                  navigate={bundle_show_path(@org, @project, bundle)}
                  class="flex items-center gap-2 text-primary hover:underline font-mono"
                >
                  <.resource_badge type="bundle" />
                  {bundle.version}
                </.link>
              </td>
              <td>
                <span
                  class={[
                    "badge badge-sm",
                    bundle.status == "compiled" && "badge-success",
                    bundle.status == "compiling" && "badge-warning",
                    bundle.status == "failed" && "badge-error",
                    bundle.status == "pending" && "badge-ghost"
                  ]}
                  data-testid="status-badge"
                >
                  {bundle.status}
                </span>
              </td>
              <td :if={@environments != []}>
                <.env_badges
                  environments={@environments}
                  promotions={Map.get(@promotions_map, bundle.id, [])}
                />
              </td>
              <td class="font-mono text-sm">
                {if bundle.size_bytes, do: format_bytes(bundle.size_bytes), else: "—"}
              </td>
              <td class="font-mono text-xs">
                {if bundle.checksum, do: String.slice(bundle.checksum, 0, 12) <> "…", else: "—"}
              </td>
              <td class="text-sm">{Calendar.strftime(bundle.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="flex gap-1">
                <.link
                  navigate={bundle_show_path(@org, @project, bundle)}
                  class="btn btn-ghost btn-xs"
                >
                  Details
                </.link>
                <button
                  :if={bundle.status in ["pending", "failed"]}
                  phx-click="delete"
                  phx-value-id={bundle.id}
                  data-confirm="Are you sure you want to delete this bundle?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@bundles == []} class="text-center py-12 text-base-content/50">
          No bundles yet. Create one to get started.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp bundle_show_path(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/new"

  defp bundle_new_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles/new"

  defp bundle_diff_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/diff"

  defp bundle_diff_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles/diff"

  defp bundle_history_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/history"

  defp bundle_history_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles/history"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  attr :environments, :list, required: true
  attr :promotions, :list, required: true

  defp env_badges(assigns) do
    promoted_env_ids = MapSet.new(assigns.promotions, & &1.environment_id)

    promoted_envs =
      assigns.environments
      |> Enum.filter(fn env -> MapSet.member?(promoted_env_ids, env.id) end)

    assigns = assign(assigns, :promoted_envs, promoted_envs)

    ~H"""
    <div class="flex flex-wrap gap-1">
      <span
        :for={env <- @promoted_envs}
        class="badge badge-xs"
        style={"background-color: #{env.color}; color: white"}
      >
        {env.name}
      </span>
      <span :if={@promoted_envs == []} class="text-base-content/40 text-xs">—</span>
    </div>
    """
  end
end
