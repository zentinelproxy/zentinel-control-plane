defmodule ZentinelCpWeb.BundlesLive.History do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Bundles, Bundles.Diff, Orgs, Projects}

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

        {bundles, diff_summaries} = Bundles.list_bundle_history(project.id)

        {:ok,
         assign(socket,
           page_title: "Version History — #{project.name}",
           org: org,
           project: project,
           bundles: bundles,
           diff_summaries: diff_summaries,
           expanded_diffs: MapSet.new(),
           inline_diffs: %{}
         )}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_event("expand_diff", %{"id" => bundle_id}, socket) do
    if MapSet.member?(socket.assigns.expanded_diffs, bundle_id) do
      {:noreply, socket}
    else
      inline_diff = compute_inline_diff(bundle_id, socket.assigns.bundles)

      {:noreply,
       socket
       |> update(:expanded_diffs, &MapSet.put(&1, bundle_id))
       |> update(:inline_diffs, &Map.put(&1, bundle_id, inline_diff))}
    end
  end

  @impl true
  def handle_event("collapse_diff", %{"id" => bundle_id}, socket) do
    {:noreply, update(socket, :expanded_diffs, &MapSet.delete(&1, bundle_id))}
  end

  @impl true
  def handle_info({event, _bundle_id}, socket)
      when event in [:bundle_compiled, :bundle_failed] do
    {bundles, diff_summaries} = Bundles.list_bundle_history(socket.assigns.project.id)

    {:noreply,
     assign(socket,
       bundles: bundles,
       diff_summaries: diff_summaries,
       expanded_diffs: MapSet.new(),
       inline_diffs: %{}
     )}
  end

  defp compute_inline_diff(bundle_id, bundles) do
    bundle_index = Enum.find_index(bundles, &(&1.id == bundle_id))

    if bundle_index && bundle_index < length(bundles) - 1 do
      newer = Enum.at(bundles, bundle_index)
      older = Enum.at(bundles, bundle_index + 1)

      config_diff = Diff.config_diff(older, newer)
      Diff.annotate_diff(config_diff)
    else
      []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Version History"
        resource_type="bundle"
        back_path={project_bundles_path(@org, @project)}
      />

      <div :if={@bundles == []} class="text-center py-12 text-base-content/50">
        No bundle versions yet.
      </div>

      <div :if={@bundles != []} class="relative ml-4" data-testid="version-timeline">
        <div class="absolute left-3 top-0 bottom-0 w-0.5 bg-base-300"></div>

        <div :for={{bundle, index} <- Enum.with_index(@bundles)} class="relative pl-10 pb-8">
          <div class={[
            "absolute left-1.5 top-1 w-3 h-3 rounded-full border-2 border-base-100",
            status_dot_class(bundle.status)
          ]}>
          </div>

          <div class="flex flex-wrap items-center gap-2 mb-1">
            <span class="font-mono font-bold" data-testid="history-version">
              {bundle.version}
            </span>
            <span class={[
              "badge badge-sm",
              bundle.status == "compiled" && "badge-success",
              bundle.status == "failed" && "badge-error",
              bundle.status in ["superseded", "revoked"] && "badge-ghost"
            ]}>
              {bundle.status}
            </span>
            <span
              :if={bundle.risk_level in ["medium", "high"]}
              class={[
                "badge badge-sm",
                bundle.risk_level == "high" && "badge-error",
                bundle.risk_level == "medium" && "badge-warning"
              ]}
            >
              {bundle.risk_level} risk
            </span>
            <span class="text-sm text-base-content/50">
              {relative_time(bundle.inserted_at)}
            </span>
          </div>

          <div
            :if={bundle.source_ref || bundle.source_branch}
            class="text-xs text-base-content/50 mb-1"
          >
            <span :if={bundle.source_branch} class="font-mono">
              {bundle.source_branch}
            </span>
            <span :if={bundle.source_ref} class="font-mono ml-1">
              ({String.slice(bundle.source_ref, 0, 7)})
            </span>
          </div>

          <%= if summary = Map.get(@diff_summaries, bundle.id) do %>
            <div class="flex flex-wrap gap-2 text-sm mb-2" data-testid="diff-stats">
              <span class="text-success">+{summary.stats.additions}</span>
              <span class="text-error">-{summary.stats.deletions}</span>

              <span
                :for={svc <- summary.semantic.services_added}
                class="badge badge-xs badge-success"
              >
                +{svc}
              </span>
              <span
                :for={svc <- summary.semantic.services_removed}
                class="badge badge-xs badge-error"
              >
                -{svc}
              </span>
              <span
                :if={summary.semantic.services_modified != []}
                class="badge badge-xs badge-warning"
              >
                {length(summary.semantic.services_modified)} modified
              </span>
              <span
                :if={summary.semantic.settings_changed}
                class="badge badge-xs badge-info"
              >
                settings changed
              </span>
            </div>

            <div class="flex flex-wrap gap-2 mb-2">
              <%= if MapSet.member?(@expanded_diffs, bundle.id) do %>
                <button
                  phx-click="collapse_diff"
                  phx-value-id={bundle.id}
                  class="btn btn-ghost btn-xs"
                >
                  Hide diff
                </button>
              <% else %>
                <button
                  phx-click="expand_diff"
                  phx-value-id={bundle.id}
                  class="btn btn-ghost btn-xs"
                  data-testid="expand-diff"
                >
                  Show diff
                </button>
              <% end %>
              <.link
                navigate={
                  diff_path(@org, @project, get_parent_id(bundle, @bundles, index), bundle.id)
                }
                class="btn btn-ghost btn-xs"
              >
                Full diff
              </.link>
              <.link
                navigate={bundle_show_path(@org, @project, bundle)}
                class="btn btn-ghost btn-xs"
              >
                View bundle
              </.link>
            </div>

            <div
              :if={MapSet.member?(@expanded_diffs, bundle.id)}
              class="mt-2 border border-base-300 rounded overflow-x-auto"
              data-testid="inline-diff"
            >
              <table class="table table-xs font-mono">
                <tbody>
                  <tr
                    :for={line <- Map.get(@inline_diffs, bundle.id, [])}
                    class={diff_row_class(line.type)}
                  >
                    <td class="text-right text-base-content/40 select-none w-10 px-2">
                      {line.number_a || ""}
                    </td>
                    <td class="text-right text-base-content/40 select-none w-10 px-2">
                      {line.number_b || ""}
                    </td>
                    <td class="select-none w-4 px-1">
                      {diff_marker(line.type)}
                    </td>
                    <td class="whitespace-pre">{line.line}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="text-sm text-base-content/50 mb-2">
              {if index == length(@bundles) - 1, do: "Initial version", else: ""}
            </div>
            <div class="flex gap-2">
              <.link
                navigate={bundle_show_path(@org, @project, bundle)}
                class="btn btn-ghost btn-xs"
              >
                View bundle
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp status_dot_class("compiled"), do: "bg-success"
  defp status_dot_class("failed"), do: "bg-error"
  defp status_dot_class(_), do: "bg-base-content/30"

  defp diff_row_class(:ins), do: "bg-success/10"
  defp diff_row_class(:del), do: "bg-error/10"
  defp diff_row_class(_), do: ""

  defp diff_marker(:ins), do: "+"
  defp diff_marker(:del), do: "-"
  defp diff_marker(_), do: " "

  defp get_parent_id(bundle, bundles, index) do
    if index < length(bundles) - 1 do
      Enum.at(bundles, index + 1).id
    else
      bundle.id
    end
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} min ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)} hours ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)} days ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp bundle_show_path(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp diff_path(%{slug: org_slug}, project, a_id, b_id),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"

  defp diff_path(nil, project, a_id, b_id),
    do: ~p"/projects/#{project.slug}/bundles/diff?a=#{a_id}&b=#{b_id}"
end
