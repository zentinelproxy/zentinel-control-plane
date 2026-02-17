defmodule ZentinelCpWeb.WafPoliciesLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Waf}
  alias ZentinelCp.Waf.WafRule

  @impl true
  def mount(%{"project_slug" => slug, "id" => policy_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         policy when not is_nil(policy) <- Waf.get_policy_with_overrides!(policy_id),
         true <- policy.project_id == project.id do
      effective_rules = Waf.get_effective_rules(policy)
      all_rules = Waf.list_rules()
      kdl_preview = generate_waf_preview(policy, effective_rules)

      {:ok,
       assign(socket,
         page_title: "WAF Policy: #{policy.name} — #{project.name}",
         org: org,
         project: project,
         policy: policy,
         effective_rules: effective_rules,
         all_rules: all_rules,
         kdl_preview: kdl_preview,
         categories: WafRule.categories()
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("set_override", params, socket) do
    policy = socket.assigns.policy
    project = socket.assigns.project
    rule_id = params["rule_id"]
    action = params["action"]

    if action == "default" do
      # Remove override
      override =
        Enum.find(policy.rule_overrides, fn o -> o.waf_rule_id == rule_id end)

      if override, do: Waf.delete_override(override)
    else
      Waf.upsert_override(%{
        waf_policy_id: policy.id,
        waf_rule_id: rule_id,
        action: action
      })
    end

    Audit.log_user_action(
      socket.assigns.current_user,
      "update_override",
      "waf_policy",
      policy.id,
      project_id: project.id
    )

    reload(socket)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    project = socket.assigns.project
    policy = socket.assigns.policy

    case Waf.delete_policy(policy) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "waf_policy", policy.id,
          project_id: project.id
        )

        {:noreply,
         push_navigate(socket, to: index_path(socket.assigns.org, project))
         |> put_flash(:info, "WAF policy deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete WAF policy.")}
    end
  end

  defp reload(socket) do
    policy = Waf.get_policy_with_overrides!(socket.assigns.policy.id)
    effective_rules = Waf.get_effective_rules(policy)
    kdl_preview = generate_waf_preview(policy, effective_rules)

    {:noreply,
     assign(socket,
       policy: policy,
       effective_rules: effective_rules,
       kdl_preview: kdl_preview
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">{@policy.name}</h1>
        <div class="flex gap-2">
          <.link navigate={edit_path(@org, @project, @policy)} class="btn btn-ghost btn-sm">
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this WAF policy?"
            class="btn btn-ghost btn-sm text-error"
          >
            Delete
          </button>
        </div>
      </div>

      <.k8s_section>
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm max-w-lg">
          <dt class="text-base-content/60">Slug</dt>
          <dd class="font-mono">{@policy.slug}</dd>
          <dt class="text-base-content/60">Mode</dt>
          <dd>
            <span class={["badge badge-sm", mode_badge(@policy.mode)]}>{@policy.mode}</span>
          </dd>
          <dt class="text-base-content/60">Sensitivity</dt>
          <dd>
            <span class={["badge badge-sm", sensitivity_badge(@policy.sensitivity)]}>
              {@policy.sensitivity}
            </span>
          </dd>
          <dt class="text-base-content/60">Default Action</dt>
          <dd>{@policy.default_action}</dd>
          <dt class="text-base-content/60">Enabled</dt>
          <dd>{if @policy.enabled, do: "Yes", else: "No"}</dd>
          <dt class="text-base-content/60">Categories</dt>
          <dd>
            <div class="flex flex-wrap gap-1">
              <span
                :for={cat <- @policy.enabled_categories || []}
                class="badge badge-xs badge-outline"
              >
                {cat}
              </span>
              <span :if={(@policy.enabled_categories || []) == []} class="text-base-content/40">
                None
              </span>
            </div>
          </dd>
          <dt :if={@policy.max_body_size} class="text-base-content/60">Max Body Size</dt>
          <dd :if={@policy.max_body_size}>{@policy.max_body_size} bytes</dd>
          <dt :if={@policy.max_header_size} class="text-base-content/60">Max Header Size</dt>
          <dd :if={@policy.max_header_size}>{@policy.max_header_size} bytes</dd>
          <dt :if={@policy.max_uri_length} class="text-base-content/60">Max URI Length</dt>
          <dd :if={@policy.max_uri_length}>{@policy.max_uri_length} bytes</dd>
          <dt :if={@policy.description} class="text-base-content/60">Description</dt>
          <dd :if={@policy.description}>{@policy.description}</dd>
        </dl>
      </.k8s_section>

      <div class="divider text-xs text-base-content/50">
        Effective Rules ({length(@effective_rules)})
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
              <th class="text-xs">Override</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{rule, effective_action} <- @effective_rules}>
              <td class="font-mono text-xs">{rule.rule_id}</td>
              <td class="text-sm">{rule.name}</td>
              <td><span class="badge badge-xs badge-outline">{rule.category}</span></td>
              <td>
                <span class={["badge badge-xs", severity_badge(rule.severity)]}>
                  {rule.severity}
                </span>
              </td>
              <td>
                <span class={["badge badge-xs", action_badge(effective_action)]}>
                  {effective_action}
                </span>
              </td>
              <td>
                <select
                  phx-change="set_override"
                  phx-value-rule_id={rule.id}
                  name="action"
                  class="select select-bordered select-xs w-28"
                >
                  <option value="default" selected={!has_override?(@policy, rule.id)}>
                    default
                  </option>
                  <option value="block" selected={override_action(@policy, rule.id) == "block"}>
                    block
                  </option>
                  <option value="log" selected={override_action(@policy, rule.id) == "log"}>
                    log
                  </option>
                  <option value="disable" selected={override_action(@policy, rule.id) == "disable"}>
                    disable
                  </option>
                </select>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@effective_rules == []} class="text-center py-8 text-base-content/50 text-sm">
          No rules active. Enable categories above to see matching rules.
        </div>
      </.k8s_section>

      <div class="divider text-xs text-base-content/50">KDL Preview</div>

      <.k8s_section>
        <pre class="text-xs bg-base-200 p-4 rounded-lg overflow-x-auto"><code>{@kdl_preview}</code></pre>
      </.k8s_section>
    </div>
    """
  end

  defp has_override?(policy, rule_id) do
    Enum.any?(policy.rule_overrides, fn o -> o.waf_rule_id == rule_id end)
  end

  defp override_action(policy, rule_id) do
    case Enum.find(policy.rule_overrides, fn o -> o.waf_rule_id == rule_id end) do
      nil -> nil
      override -> override.action
    end
  end

  defp generate_waf_preview(policy, effective_rules) do
    lines = ["waf {"]
    lines = lines ++ ["    mode #{inspect(policy.mode)}"]
    lines = lines ++ ["    sensitivity #{inspect(policy.sensitivity)}"]

    lines =
      if policy.max_body_size,
        do: lines ++ ["    max_body_size #{policy.max_body_size}"],
        else: lines

    by_category =
      effective_rules
      |> Enum.group_by(fn {rule, _action} -> rule.category end)
      |> Enum.sort_by(fn {cat, _} -> cat end)

    category_lines =
      Enum.flat_map(by_category, fn {category, rules_with_actions} ->
        rule_lines =
          Enum.map(rules_with_actions, fn {rule, action} ->
            "        rule #{inspect(rule.rule_id)} action=#{inspect(action)}"
          end)

        ["    category #{inspect(category)} {"] ++ rule_lines ++ ["    }"]
      end)

    kdl = lines ++ category_lines ++ ["}"]
    Enum.join(kdl, "\n")
  end

  defp mode_badge("block"), do: "badge-error"
  defp mode_badge("detect_only"), do: "badge-warning"
  defp mode_badge("challenge"), do: "badge-info"
  defp mode_badge(_), do: "badge-ghost"

  defp sensitivity_badge("paranoid"), do: "badge-error"
  defp sensitivity_badge("high"), do: "badge-warning"
  defp sensitivity_badge("medium"), do: "badge-info"
  defp sensitivity_badge("low"), do: "badge-ghost"
  defp sensitivity_badge(_), do: "badge-ghost"

  defp severity_badge("critical"), do: "badge-error"
  defp severity_badge("high"), do: "badge-warning"
  defp severity_badge("medium"), do: "badge-info"
  defp severity_badge("low"), do: "badge-ghost"
  defp severity_badge(_), do: "badge-ghost"

  defp action_badge("block"), do: "badge-error"
  defp action_badge("log"), do: "badge-warning"
  defp action_badge(_), do: "badge-ghost"

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp edit_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies/#{policy.id}/edit"

  defp edit_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/waf/policies/#{policy.id}/edit"

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf/policies"
end
