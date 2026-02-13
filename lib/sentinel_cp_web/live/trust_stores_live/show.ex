defmodule SentinelCpWeb.TrustStoresLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => ts_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         ts when not is_nil(ts) <- Services.get_trust_store(ts_id),
         true <- ts.project_id == project.id do
      # Find upstream groups linked to this trust store
      linked_groups =
        Services.list_upstream_groups(project.id)
        |> Enum.filter(&(&1.trust_store_id == ts.id))

      {:ok,
       assign(socket,
         page_title: "Trust Store #{ts.name} — #{project.name}",
         org: org,
         project: project,
         trust_store: ts,
         linked_groups: linked_groups
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    ts = socket.assigns.trust_store
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_trust_store(ts) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "trust_store", ts.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Trust store deleted.")
         |> push_navigate(to: ts_index_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete trust store.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@trust_store.name}
        resource_type="trust store"
        back_path={ts_index_path(@org, @project)}
      >
        <:action>
          <.link
            navigate={ts_edit_path(@org, @project, @trust_store)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <a
            href={~p"/api/v1/projects/#{@project.slug}/trust-stores/#{@trust_store.id}/download"}
            class="btn btn-outline btn-sm"
            download={"#{@trust_store.slug}.pem"}
          >
            Download PEM
          </a>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this trust store?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Trust Store Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@trust_store.id}</span></:item>
            <:item label="Name">{@trust_store.name}</:item>
            <:item label="Slug"><span class="font-mono">{@trust_store.slug}</span></:item>
            <:item label="Description">{@trust_store.description || "—"}</:item>
            <:item label="Certificate Count">{@trust_store.cert_count}</:item>
            <:item label="Subjects">{format_subjects(@trust_store.subjects)}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Expiry & Linked Resources">
          <.definition_list>
            <:item label="Earliest Expiry">
              {if @trust_store.earliest_expiry,
                do: Calendar.strftime(@trust_store.earliest_expiry, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Latest Expiry">
              {if @trust_store.latest_expiry,
                do: Calendar.strftime(@trust_store.latest_expiry, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Created">
              {Calendar.strftime(@trust_store.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
            <:item label="Linked Upstream Groups">
              <%= if @linked_groups == [] do %>
                <span class="text-base-content/50">None</span>
              <% else %>
                <div class="flex flex-wrap gap-1">
                  <.link
                    :for={group <- @linked_groups}
                    navigate={group_show_path(@org, @project, group)}
                    class="badge badge-sm badge-outline hover:badge-primary cursor-pointer"
                  >
                    {group.name}
                  </.link>
                </div>
              <% end %>
            </:item>
          </.definition_list>
        </.k8s_section>

        <div class="lg:col-span-2">
          <.k8s_section title="Certificates PEM">
            <pre class="bg-base-300 p-4 rounded text-xs font-mono whitespace-pre-wrap overflow-x-auto max-h-64 overflow-y-auto">{@trust_store.certificates_pem}</pre>
          </.k8s_section>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp ts_index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores"

  defp ts_index_path(nil, project),
    do: ~p"/projects/#{project.slug}/trust-stores"

  defp ts_edit_path(%{slug: org_slug}, project, ts),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores/#{ts.id}/edit"

  defp ts_edit_path(nil, project, ts),
    do: ~p"/projects/#{project.slug}/trust-stores/#{ts.id}/edit"

  defp group_show_path(%{slug: org_slug}, project, group),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp group_show_path(nil, project, group),
    do: ~p"/projects/#{project.slug}/upstream-groups/#{group.id}"

  defp format_subjects(nil), do: "—"
  defp format_subjects([]), do: "—"
  defp format_subjects(subjects), do: Enum.join(subjects, ", ")
end
