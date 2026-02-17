defmodule ZentinelCpWeb.AuthPoliciesLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        policies = Services.list_auth_policies(project.id)

        {:ok,
         assign(socket,
           page_title: "Auth Policies — #{project.name}",
           org: org,
           project: project,
           policies: policies
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project
    policy = Services.get_auth_policy!(id)

    case Services.delete_auth_policy(policy) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "auth_policy", policy.id,
          project_id: project.id
        )

        policies = Services.list_auth_policies(project.id)
        {:noreply, assign(socket, policies: policies) |> put_flash(:info, "Auth policy deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete auth policy.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Auth Policies</h1>
        <.link navigate={new_path(@org, @project)} class="btn btn-primary btn-sm">
          New Auth Policy
        </.link>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Type</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs">Created</th>
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
              <td><span class="badge badge-sm badge-outline">{policy.auth_type}</span></td>
              <td>
                <span class={["badge badge-xs", (policy.enabled && "badge-success") || "badge-ghost"]}>
                  {if policy.enabled, do: "yes", else: "no"}
                </span>
              </td>
              <td class="text-sm">{Calendar.strftime(policy.inserted_at, "%Y-%m-%d")}</td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={policy.id}
                  data-confirm="Are you sure you want to delete this auth policy?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@policies == []} class="text-center py-8 text-base-content/50 text-sm">
          No auth policies yet. Create one to configure proxy-level authentication.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies/new"

  defp new_path(nil, project),
    do: ~p"/projects/#{project.slug}/auth-policies/new"

  defp show_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies/#{policy.id}"

  defp show_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/auth-policies/#{policy.id}"
end
