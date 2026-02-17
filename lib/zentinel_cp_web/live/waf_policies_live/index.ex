defmodule ZentinelCpWeb.WafPoliciesLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Waf}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        policies = Waf.list_policies(project.id)

        {:ok,
         assign(socket,
           page_title: "WAF Policies — #{project.name}",
           org: org,
           project: project,
           policies: policies
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project
    policy = Waf.get_policy!(id)

    case Waf.delete_policy(policy) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "waf_policy", policy.id,
          project_id: project.id
        )

        policies = Waf.list_policies(project.id)

        {:noreply, assign(socket, policies: policies) |> put_flash(:info, "WAF policy deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete WAF policy.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">WAF Policies</h1>
        <div class="flex gap-2">
          <.link navigate={rules_path(@org, @project)} class="btn btn-ghost btn-sm">
            Rule Catalog
          </.link>
          <.link navigate={new_path(@org, @project)} class="btn btn-primary btn-sm">
            New WAF Policy
          </.link>
        </div>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Mode</th>
              <th class="text-xs">Sensitivity</th>
              <th class="text-xs">Categories</th>
              <th class="text-xs">Services</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={policy <- @policies}>
              <td>
                <.link navigate={show_path(@org, @project, policy)} class="link link-primary">
                  {policy.name}
                </.link>
              </td>
              <td><span class={["badge badge-sm", mode_badge(policy.mode)]}>{policy.mode}</span></td>
              <td>
                <span class={["badge badge-sm", sensitivity_badge(policy.sensitivity)]}>
                  {policy.sensitivity}
                </span>
              </td>
              <td class="text-xs">{length(policy.enabled_categories || [])}</td>
              <td class="text-xs">{length(policy.services)}</td>
              <td>
                <span class={[
                  "badge badge-xs",
                  (policy.enabled && "badge-success") || "badge-ghost"
                ]}>
                  {if policy.enabled, do: "yes", else: "no"}
                </span>
              </td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={policy.id}
                  data-confirm="Are you sure you want to delete this WAF policy?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@policies == []} class="text-center py-8 text-base-content/50 text-sm">
          No WAF policies yet. Create one to configure Web Application Firewall rules.
        </div>
      </.k8s_section>
    </div>
    """
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

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies/new"

  defp new_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf/policies/new"

  defp show_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies/#{policy.id}"

  defp show_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/waf/policies/#{policy.id}"

  defp rules_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/rules"

  defp rules_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf/rules"
end
