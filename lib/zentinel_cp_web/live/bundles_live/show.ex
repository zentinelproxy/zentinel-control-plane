defmodule ZentinelCpWeb.BundlesLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Bundles, Orgs, Projects, Nodes}
  alias ZentinelCp.Bundles.Sbom

  @impl true
  def mount(%{"project_slug" => slug, "id" => bundle_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         bundle when not is_nil(bundle) <- Bundles.get_bundle_with_parent(bundle_id),
         true <- bundle.project_id == project.id do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "bundles:#{project.id}")
      end

      assigned_nodes = get_assigned_nodes(bundle, project.id)
      previous_bundle = Bundles.get_previous_bundle(bundle, project.id)
      environments = Projects.list_environments(project.id)
      promotions = Bundles.list_bundle_promotions(bundle.id)
      sbom_components = get_sbom_components(bundle)

      {:ok,
       assign(socket,
         page_title: "Bundle #{bundle.version} — #{project.name}",
         org: org,
         project: project,
         bundle: bundle,
         assigned_nodes: assigned_nodes,
         previous_bundle: previous_bundle,
         environments: environments,
         promotions: promotions,
         sbom_components: sbom_components
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_info({:bundle_compiled, bundle_id}, socket) do
    if bundle_id == socket.assigns.bundle.id do
      bundle = Bundles.get_bundle!(bundle_id)
      {:noreply, assign(socket, bundle: bundle)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:bundle_failed, bundle_id}, socket) do
    if bundle_id == socket.assigns.bundle.id do
      bundle = Bundles.get_bundle!(bundle_id)
      {:noreply, assign(socket, bundle: bundle)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke", _, socket) do
    bundle = socket.assigns.bundle

    case Bundles.revoke_bundle(bundle) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "revoke", "bundle", bundle.id,
          project_id: socket.assigns.project.id
        )

        {:noreply, socket |> assign(bundle: updated) |> put_flash(:info, "Bundle revoked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke bundle.")}
    end
  end

  def handle_event("delete", _, socket) do
    bundle = socket.assigns.bundle
    project = socket.assigns.project
    org = socket.assigns.org

    case Bundles.delete_bundle(bundle) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "bundle", bundle.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Bundle deleted.")
         |> push_navigate(to: project_bundles_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete bundle.")}
    end
  end

  def handle_event("promote", %{"environment-id" => env_id}, socket) do
    bundle = socket.assigns.bundle
    current_user = socket.assigns.current_user

    case Bundles.promote_bundle(bundle.id, env_id, promoted_by_id: current_user.id) do
      {:ok, _promotion} ->
        Audit.log_user_action(current_user, "promote", "bundle", bundle.id,
          project_id: socket.assigns.project.id,
          metadata: %{environment_id: env_id}
        )

        promotions = Bundles.list_bundle_promotions(bundle.id)

        {:noreply,
         socket
         |> assign(promotions: promotions)
         |> put_flash(:info, "Bundle promoted successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        error = format_changeset_error(changeset)
        {:noreply, put_flash(socket, :error, "Could not promote bundle: #{error}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not promote bundle: #{inspect(reason)}")}
    end
  end

  defp format_changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@bundle.version}
        resource_type="bundle"
        back_path={project_bundles_path(@org, @project)}
      >
        <:badge>
          <span
            class={[
              "badge badge-sm",
              @bundle.status == "compiled" && "badge-success",
              @bundle.status == "compiling" && "badge-warning",
              @bundle.status == "failed" && "badge-error",
              @bundle.status == "pending" && "badge-ghost"
            ]}
            data-testid="bundle-status"
          >
            {@bundle.status}
          </span>
        </:badge>
        <:action>
          <.link
            :if={@previous_bundle}
            navigate={diff_path(@org, @project, @previous_bundle.id, @bundle.id)}
            class="btn btn-outline btn-sm"
          >
            Compare with previous
          </.link>
          <a
            :if={@bundle.status == "compiled"}
            href={"/api/v1/projects/#{@project.slug}/bundles/#{@bundle.id}/sbom"}
            class="btn btn-outline btn-sm"
            target="_blank"
          >
            Download SBOM
          </a>
          <button
            :if={@bundle.status == "compiled"}
            phx-click="revoke"
            data-confirm="Are you sure you want to revoke this bundle?"
            class="btn btn-warning btn-sm"
          >
            Revoke
          </button>
          <button
            :if={@bundle.status in ["pending", "failed"]}
            phx-click="delete"
            data-confirm="Are you sure you want to delete this bundle?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div :if={@environments != [] and @bundle.status == "compiled"} class="mb-4">
        <.k8s_section title="Promotion Pipeline">
          <div class="flex flex-wrap items-center gap-2">
            <%= for {env, index} <- Enum.with_index(@environments) do %>
              <.promotion_badge
                environment={env}
                promoted={is_promoted?(@promotions, env.id)}
                can_promote={can_promote?(@promotions, @environments, env)}
                is_last={index == length(@environments) - 1}
              />
              <span :if={index < length(@environments) - 1} class="text-base-content/30">→</span>
            <% end %>
          </div>
        </.k8s_section>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Metadata">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@bundle.id}</span></:item>
            <:item label="Version">
              <span class="font-mono" data-testid="bundle-version">{@bundle.version}</span>
            </:item>
            <:item label="Status">{@bundle.status}</:item>
            <:item label="Checksum">
              <span class="font-mono text-sm">{@bundle.checksum || "—"}</span>
            </:item>
            <:item label="Size">
              <span class="font-mono">
                {if @bundle.size_bytes, do: format_bytes(@bundle.size_bytes), else: "—"}
              </span>
            </:item>
            <:item label="Risk Level">{@bundle.risk_level}</:item>
            <:item :if={@bundle.parent_bundle} label="Parent Version">
              <.link
                navigate={bundle_show_path_for(@org, @project, @bundle.parent_bundle)}
                class="text-primary hover:underline font-mono"
              >
                {@bundle.parent_bundle.version}
              </.link>
            </:item>
            <:item label="Created">
              {Calendar.strftime(@bundle.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Assigned Nodes">
          <div :if={@assigned_nodes == []} class="text-base-content/50 text-sm">
            No nodes assigned to this bundle.
          </div>
          <table :if={@assigned_nodes != []} class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Name</th>
                <th class="text-xs uppercase">Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={node <- @assigned_nodes}>
                <td>
                  <.link
                    navigate={node_show_path(@org, @project, node)}
                    class="flex items-center gap-2 text-primary hover:underline"
                  >
                    <.resource_badge type="node" />
                    {node.name}
                  </.link>
                </td>
                <td>
                  <span class={[
                    "badge badge-sm",
                    node.status == "online" && "badge-success",
                    node.status == "offline" && "badge-error",
                    "badge-ghost"
                  ]}>
                    {node.status}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </.k8s_section>

        <div :if={@bundle.compiler_output} class="lg:col-span-2">
          <.k8s_section title="Compiler Output">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto">{@bundle.compiler_output}</pre>
          </.k8s_section>
        </div>

        <div class="lg:col-span-2">
          <.k8s_section title="Configuration Source">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto">{@bundle.config_source}</pre>
          </.k8s_section>
        </div>

        <div :if={@bundle.manifest != %{}} class="lg:col-span-2">
          <.k8s_section title="Manifest">
            <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto">{Jason.encode!(@bundle.manifest, pretty: true)}</pre>
          </.k8s_section>
        </div>

        <div :if={@bundle.status == "compiled"} class="lg:col-span-2">
          <.k8s_section title="Software Bill of Materials (SBOM)">
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <div class="text-sm text-base-content/50">
                  CycloneDX 1.5 format • {length(@sbom_components)} component(s)
                </div>
                <a
                  href={"/api/v1/projects/#{@project.slug}/bundles/#{@bundle.id}/sbom"}
                  class="btn btn-outline btn-xs"
                  target="_blank"
                >
                  Download JSON
                </a>
              </div>

              <div :if={@sbom_components == []} class="text-base-content/50 text-sm">
                No components detected in configuration.
              </div>

              <table :if={@sbom_components != []} class="table table-sm">
                <thead class="bg-base-300">
                  <tr>
                    <th class="text-xs uppercase">Component</th>
                    <th class="text-xs uppercase">Type</th>
                    <th class="text-xs uppercase">Group</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={component <- @sbom_components}>
                    <td class="font-mono text-sm">{component["name"]}</td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        component["type"] == "framework" && "badge-primary",
                        component["type"] == "library" && "badge-ghost"
                      ]}>
                        {component["type"]}
                      </span>
                    </td>
                    <td class="text-sm text-base-content/70">{component["group"]}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.k8s_section>
        </div>
      </div>
    </div>
    """
  end

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp node_show_path(%{slug: org_slug}, project, node),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"

  defp node_show_path(nil, project, node),
    do: ~p"/projects/#{project.slug}/nodes/#{node.id}"

  defp get_assigned_nodes(bundle, project_id) do
    Nodes.list_nodes(project_id)
    |> Enum.filter(fn node ->
      node.staged_bundle_id == bundle.id || node.active_bundle_id == bundle.id
    end)
  end

  defp bundle_show_path_for(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path_for(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp diff_path(%{slug: org_slug}, project, a_id, b_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"

  defp diff_path(nil, project, a_id, b_id),
    do: ~p"/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp get_sbom_components(bundle) do
    case Sbom.generate(bundle) do
      {:ok, sbom} -> sbom["components"] || []
      _ -> []
    end
  end

  defp is_promoted?(promotions, env_id) do
    Enum.any?(promotions, fn p -> p.environment_id == env_id end)
  end

  defp can_promote?(promotions, environments, env) do
    # Can promote to first environment if not already promoted
    # Can promote to subsequent environments if promoted to previous one
    env_index = Enum.find_index(environments, fn e -> e.id == env.id end)

    cond do
      is_promoted?(promotions, env.id) ->
        false

      env_index == 0 ->
        true

      true ->
        prev_env = Enum.at(environments, env_index - 1)
        is_promoted?(promotions, prev_env.id)
    end
  end

  attr :environment, :map, required: true
  attr :promoted, :boolean, required: true
  attr :can_promote, :boolean, required: true
  attr :is_last, :boolean, required: true

  defp promotion_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <span
        :if={@promoted}
        class="badge badge-sm"
        style={"background-color: #{@environment.color}; color: white"}
      >
        <.icon name="hero-check" class="w-3 h-3 mr-1" />
        {@environment.name}
      </span>
      <span :if={!@promoted and !@can_promote} class="badge badge-sm badge-ghost badge-outline">
        {@environment.name}
      </span>
      <button
        :if={!@promoted and @can_promote}
        phx-click="promote"
        phx-value-environment-id={@environment.id}
        class="btn btn-xs btn-outline"
        style={"border-color: #{@environment.color}; color: #{@environment.color}"}
      >
        Promote to {@environment.name}
      </button>
    </div>
    """
  end
end
