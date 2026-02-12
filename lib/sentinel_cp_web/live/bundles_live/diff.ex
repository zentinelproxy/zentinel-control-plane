defmodule SentinelCpWeb.BundlesLive.Diff do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Bundles, Bundles.Diff, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        bundles = Bundles.list_bundles(project.id)
        bundle_a_id = params["a"]
        bundle_b_id = params["b"]

        bundle_a = if bundle_a_id, do: Bundles.get_bundle(bundle_a_id)
        bundle_b = if bundle_b_id, do: Bundles.get_bundle(bundle_b_id)

        {diff, stats, manifest_diff, semantic, paired} = compute_diff(bundle_a, bundle_b)

        {:ok,
         assign(socket,
           page_title: "Compare Bundles — #{project.name}",
           org: org,
           project: project,
           bundles: bundles,
           bundle_a: bundle_a,
           bundle_b: bundle_b,
           bundle_a_id: bundle_a_id || "",
           bundle_b_id: bundle_b_id || "",
           diff_lines: diff,
           diff_stats: stats,
           manifest_diff: manifest_diff,
           semantic: semantic,
           paired_lines: paired,
           view_mode: :unified,
           fullscreen: false
         )}
    end
  end

  @impl true
  def handle_event("compare", %{"a" => a_id, "b" => b_id}, socket) do
    project = socket.assigns.project
    org = socket.assigns.org

    path = diff_path(org, project, a_id, b_id)
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("toggle_view_mode", _, socket) do
    new_mode = if socket.assigns.view_mode == :unified, do: :side_by_side, else: :unified
    {:noreply, assign(socket, view_mode: new_mode)}
  end

  @impl true
  def handle_event("toggle_fullscreen", _, socket) do
    {:noreply, assign(socket, fullscreen: !socket.assigns.fullscreen)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Compare Bundles"
        resource_type="bundle"
        back_path={project_bundles_path(@org, @project)}
      >
        <:badge>
          <span :if={@bundle_a && @bundle_b} class="text-sm font-normal text-base-content/70">
            <span data-testid="diff-from">{@bundle_a.version}</span>
            → <span data-testid="diff-to">{@bundle_b.version}</span>
          </span>
        </:badge>
      </.detail_header>

      <.table_toolbar>
        <:filters>
          <form phx-submit="compare" class="flex items-end gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Bundle A (base)</span></label>
              <select name="a" class="select select-bordered select-sm">
                <option value="">Select bundle</option>
                <option :for={b <- @bundles} value={b.id} selected={b.id == @bundle_a_id}>
                  {b.version} ({b.status})
                </option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Bundle B (new)</span></label>
              <select name="b" class="select select-bordered select-sm">
                <option value="">Select bundle</option>
                <option :for={b <- @bundles} value={b.id} selected={b.id == @bundle_b_id}>
                  {b.version} ({b.status})
                </option>
              </select>
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Compare</button>
          </form>
        </:filters>
      </.table_toolbar>

      <%!-- Semantic Summary --%>
      <div :if={@semantic} class="flex flex-wrap gap-2 text-sm">
        <span :if={@semantic.services_added != []} class="badge badge-success badge-sm">
          +{length(@semantic.services_added)} added
        </span>
        <span :if={@semantic.services_removed != []} class="badge badge-error badge-sm">
          -{length(@semantic.services_removed)} removed
        </span>
        <span :if={@semantic.services_modified != []} class="badge badge-warning badge-sm">
          {length(@semantic.services_modified)} modified
        </span>
        <span :if={@semantic.settings_changed} class="badge badge-info badge-sm">
          settings changed
        </span>
      </div>

      <div :if={@diff_stats} class="flex gap-4 text-sm">
        <span class="text-success">+{@diff_stats.additions} additions</span>
        <span class="text-error">-{@diff_stats.deletions} deletions</span>
        <span class="text-base-content/50">{@diff_stats.unchanged} unchanged</span>
      </div>

      <%!-- View Mode Toggle --%>
      <div :if={@diff_lines} class="flex gap-2">
        <button
          phx-click="toggle_view_mode"
          class={["btn btn-xs", (@view_mode == :unified && "btn-primary") || "btn-ghost"]}
        >
          Unified
        </button>
        <button
          phx-click="toggle_view_mode"
          class={["btn btn-xs", (@view_mode == :side_by_side && "btn-primary") || "btn-ghost"]}
        >
          Side by Side
        </button>
        <button phx-click="toggle_fullscreen" class="btn btn-xs btn-ghost">
          {if @fullscreen, do: "Exit Fullscreen", else: "Fullscreen"}
        </button>
      </div>

      <%!-- Fullscreen overlay --%>
      <div
        :if={@fullscreen && @diff_lines}
        class="fixed inset-0 z-50 bg-base-100 p-4 overflow-auto"
      >
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-lg font-bold">Configuration Diff</h2>
          <button phx-click="toggle_fullscreen" class="btn btn-sm btn-ghost">
            Close
          </button>
        </div>
        {render_diff_content(assigns)}
      </div>

      <%!-- Normal diff view --%>
      <div :if={@diff_lines && !@fullscreen}>
        <.k8s_section title="Configuration Diff">
          {render_diff_content(assigns)}
        </.k8s_section>
      </div>

      <div :if={@manifest_diff}>
        <.k8s_section title="Manifest Diff">
          <div :if={@manifest_diff.added != []} class="mb-2">
            <h3 class="text-sm font-medium text-success mb-1">Added files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.added}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.removed != []} class="mb-2">
            <h3 class="text-sm font-medium text-error mb-1">Removed files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.removed}>{f}</li>
            </ul>
          </div>
          <div :if={@manifest_diff.modified != []} class="mb-2">
            <h3 class="text-sm font-medium text-warning mb-1">Modified files</h3>
            <ul class="list-disc list-inside text-sm font-mono">
              <li :for={f <- @manifest_diff.modified}>{f}</li>
            </ul>
          </div>
          <div
            :if={
              @manifest_diff.added == [] and @manifest_diff.removed == [] and
                @manifest_diff.modified == []
            }
            class="text-base-content/50 text-sm"
          >
            No manifest changes.
          </div>
        </.k8s_section>
      </div>

      <div :if={is_nil(@bundle_a) or is_nil(@bundle_b)} class="text-center py-12 text-base-content/50">
        Select two bundles above to compare their configurations.
      </div>
    </div>
    """
  end

  defp render_diff_content(assigns) do
    if assigns.view_mode == :side_by_side do
      render_side_by_side(assigns)
    else
      render_unified(assigns)
    end
  end

  defp render_unified(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-xs font-mono">
        <tbody>
          <tr :for={line <- @diff_lines} class={diff_row_class(line.type)}>
            <td class="text-right text-base-content/40 select-none w-12 px-2">
              {line.number_a || ""}
            </td>
            <td class="text-right text-base-content/40 select-none w-12 px-2">
              {line.number_b || ""}
            </td>
            <td class="select-none w-6 px-1">
              {diff_marker(line.type)}
            </td>
            <td class="whitespace-pre">{line.line}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_side_by_side(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-xs font-mono w-full">
        <thead>
          <tr>
            <th class="w-12 text-center">#</th>
            <th class="w-1/2">Base</th>
            <th class="w-12 text-center">#</th>
            <th class="w-1/2">New</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={pair <- @paired_lines}>
            <td class={["text-right text-base-content/40 select-none w-12 px-2", pair.left && diff_row_class(pair.left.type)]}>
              {pair.left && pair.left.number_a || ""}
            </td>
            <td class={["whitespace-pre", pair.left && diff_row_class(pair.left.type)]}>
              {pair.left && pair.left.line || ""}
            </td>
            <td class={["text-right text-base-content/40 select-none w-12 px-2", pair.right && diff_row_class(pair.right.type)]}>
              {pair.right && pair.right.number_b || ""}
            </td>
            <td class={["whitespace-pre", pair.right && diff_row_class(pair.right.type)]}>
              {pair.right && pair.right.line || ""}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp compute_diff(nil, _), do: {nil, nil, nil, nil, nil}
  defp compute_diff(_, nil), do: {nil, nil, nil, nil, nil}

  defp compute_diff(bundle_a, bundle_b) do
    config_diff = Diff.config_diff(bundle_a, bundle_b)
    lines = Diff.annotate_diff(config_diff)
    stats = Diff.diff_stats(config_diff)
    manifest = Diff.manifest_diff(bundle_a, bundle_b)
    semantic = Diff.semantic_diff(bundle_a, bundle_b)
    paired = Diff.side_by_side_diff(lines)
    {lines, stats, manifest, semantic, paired}
  end

  defp diff_row_class(:ins), do: "bg-success/10"
  defp diff_row_class(:del), do: "bg-error/10"
  defp diff_row_class(_), do: ""

  defp diff_marker(:ins), do: "+"
  defp diff_marker(:del), do: "-"
  defp diff_marker(_), do: " "

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp diff_path(%{slug: org_slug}, project, a_id, b_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"

  defp diff_path(nil, project, a_id, b_id),
    do: ~p"/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"
end
