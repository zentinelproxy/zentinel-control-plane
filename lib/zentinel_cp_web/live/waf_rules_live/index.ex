defmodule ZentinelCpWeb.WafRulesLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Projects, Waf}
  alias ZentinelCp.Waf.WafRule

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        rules = Waf.list_rules()

        {:ok,
         assign(socket,
           page_title: "WAF Rules — #{project.name}",
           org: org,
           project: project,
           rules: rules,
           category_filter: nil,
           severity_filter: nil,
           search: ""
         )}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    category = if params["category"] == "", do: nil, else: params["category"]
    severity = if params["severity"] == "", do: nil, else: params["severity"]
    search = params["search"] || ""

    opts =
      [category: category, severity: severity]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    opts = if search != "", do: Keyword.put(opts, :search, search), else: opts

    rules = Waf.list_rules(opts)

    {:noreply,
     assign(socket,
       rules: rules,
       category_filter: category,
       severity_filter: severity,
       search: search
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">WAF Rule Catalog</h1>
        <span class="badge badge-ghost">{length(@rules)} rules</span>
      </div>

      <div class="flex gap-2 flex-wrap">
        <form phx-change="filter" class="flex gap-2 flex-wrap items-end">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Category</span></label>
            <select name="category" class="select select-bordered select-sm w-40">
              <option value="">All categories</option>
              <option
                :for={cat <- WafRule.categories()}
                value={cat}
                selected={cat == @category_filter}
              >
                {cat}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Severity</span></label>
            <select name="severity" class="select select-bordered select-sm w-32">
              <option value="">All severities</option>
              <option
                :for={sev <- WafRule.severities()}
                value={sev}
                selected={sev == @severity_filter}
              >
                {sev}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Search</span></label>
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Rule ID or name..."
              class="input input-bordered input-sm w-48"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Rule ID</th>
              <th class="text-xs">Name</th>
              <th class="text-xs">Category</th>
              <th class="text-xs">Severity</th>
              <th class="text-xs">Action</th>
              <th class="text-xs">Phase</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rule <- @rules}>
              <td class="font-mono text-xs">{rule.rule_id}</td>
              <td>{rule.name}</td>
              <td><span class="badge badge-sm badge-outline">{rule.category}</span></td>
              <td>
                <span class={["badge badge-xs", severity_badge(rule.severity)]}>
                  {rule.severity}
                </span>
              </td>
              <td class="text-xs">{rule.default_action}</td>
              <td class="text-xs">{rule.phase}</td>
            </tr>
          </tbody>
        </table>

        <div :if={@rules == []} class="text-center py-8 text-base-content/50 text-sm">
          No rules match the current filters.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp severity_badge("critical"), do: "badge-error"
  defp severity_badge("high"), do: "badge-warning"
  defp severity_badge("medium"), do: "badge-info"
  defp severity_badge("low"), do: "badge-ghost"
  defp severity_badge(_), do: "badge-ghost"

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil
end
