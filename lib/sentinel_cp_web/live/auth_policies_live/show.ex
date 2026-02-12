defmodule SentinelCpWeb.AuthPoliciesLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => policy_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         policy when not is_nil(policy) <- Services.get_auth_policy(policy_id),
         true <- policy.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Auth Policy #{policy.name} — #{project.name}",
         org: org,
         project: project,
         policy: policy
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    policy = socket.assigns.policy
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_auth_policy(policy) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "auth_policy", policy.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Auth policy deleted.")
         |> push_navigate(to: index_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete auth policy.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@policy.name}
        resource_type="auth policy"
        back_path={index_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@policy.enabled && "badge-success") || "badge-ghost"]}>
            {if @policy.enabled, do: "enabled", else: "disabled"}
          </span>
        </:badge>
        <:action>
          <.link
            navigate={edit_path(@org, @project, @policy)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this auth policy?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@policy.id}</span></:item>
            <:item label="Name">{@policy.name}</:item>
            <:item label="Slug"><span class="font-mono">{@policy.slug}</span></:item>
            <:item label="Description">{@policy.description || "—"}</:item>
            <:item label="Auth Type"><span class="badge badge-sm badge-outline">{@policy.auth_type}</span></:item>
            <:item label="Enabled">{if @policy.enabled, do: "Yes", else: "No"}</:item>
            <:item label="Created">{Calendar.strftime(@policy.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Configuration">
          <.definition_list>
            <:item :for={{key, value} <- Enum.sort(@policy.config || %{})} label={key}>
              <span class="font-mono text-sm">{value}</span>
            </:item>
          </.definition_list>
          <div :if={@policy.config == nil || @policy.config == %{}} class="text-center py-4 text-base-content/50 text-sm">
            No configuration set.
          </div>
        </.k8s_section>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/auth-policies"

  defp edit_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies/#{policy.id}/edit"

  defp edit_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/auth-policies/#{policy.id}/edit"
end
