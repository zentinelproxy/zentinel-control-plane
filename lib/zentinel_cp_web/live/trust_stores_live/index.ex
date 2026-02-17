defmodule ZentinelCpWeb.TrustStoresLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        trust_stores = Services.list_trust_stores(project.id)

        {:ok,
         assign(socket,
           page_title: "Trust Stores — #{project.name}",
           org: org,
           project: project,
           trust_stores: trust_stores
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    ts = Services.get_trust_store!(id)
    project = socket.assigns.project

    case Services.delete_trust_store(ts) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "trust_store", ts.id,
          project_id: project.id
        )

        trust_stores = Services.list_trust_stores(project.id)

        {:noreply,
         socket
         |> assign(trust_stores: trust_stores)
         |> put_flash(:info, "Trust store deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete trust store.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Trust Stores</h1>
        </:filters>
        <:actions>
          <.link navigate={ts_new_path(@org, @project)} class="btn btn-primary btn-sm">
            Add Trust Store
          </.link>
        </:actions>
      </.table_toolbar>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Cert Count</th>
              <th class="text-xs uppercase">Subjects</th>
              <th class="text-xs uppercase">Earliest Expiry</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ts <- @trust_stores}>
              <td>
                <.link
                  navigate={ts_show_path(@org, @project, ts)}
                  class="text-primary hover:underline font-mono"
                >
                  {ts.name}
                </.link>
              </td>
              <td class="text-sm">{ts.cert_count}</td>
              <td class="text-sm">{Enum.join(ts.subjects || [], ", ")}</td>
              <td class="text-sm">
                {if ts.earliest_expiry,
                  do: Calendar.strftime(ts.earliest_expiry, "%Y-%m-%d"),
                  else: "—"}
              </td>
              <td class="flex gap-1">
                <.link navigate={ts_show_path(@org, @project, ts)} class="btn btn-ghost btn-xs">
                  Details
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={ts.id}
                  data-confirm="Are you sure? Upstream groups using this trust store will lose their TLS verification reference."
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@trust_stores == []} class="text-center py-12 text-base-content/50">
          No trust stores yet. Add one to enable upstream TLS verification.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp ts_new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores/new"

  defp ts_new_path(nil, project),
    do: ~p"/projects/#{project.slug}/trust-stores/new"

  defp ts_show_path(%{slug: org_slug}, project, ts),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores/#{ts.id}"

  defp ts_show_path(nil, project, ts),
    do: ~p"/projects/#{project.slug}/trust-stores/#{ts.id}"
end
