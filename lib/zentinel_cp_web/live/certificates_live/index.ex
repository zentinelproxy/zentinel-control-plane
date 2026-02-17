defmodule ZentinelCpWeb.CertificatesLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        certs = Services.list_certificates(project.id)

        {:ok,
         assign(socket,
           page_title: "Certificates — #{project.name}",
           org: org,
           project: project,
           certificates: certs
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project

    with cert when not is_nil(cert) <- Services.get_certificate(id),
         true <- cert.project_id == project.id do
      case Services.delete_certificate(cert) do
        {:ok, _} ->
          Audit.log_user_action(socket.assigns.current_user, "delete", "certificate", cert.id,
            project_id: project.id
          )

          certs = Services.list_certificates(project.id)

          {:noreply,
           socket
           |> assign(certificates: certs)
           |> put_flash(:info, "Certificate deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete certificate.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Certificate not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Certificates</h1>
        </:filters>
        <:actions>
          <.link navigate={cert_new_path(@org, @project)} class="btn btn-primary btn-sm">
            Upload Certificate
          </.link>
        </:actions>
      </.table_toolbar>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Domain</th>
              <th class="text-xs uppercase">Status</th>
              <th class="text-xs uppercase">Expires</th>
              <th class="text-xs uppercase">Issuer</th>
              <th class="text-xs uppercase">Last Renewal</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={cert <- @certificates}>
              <td>
                <.link
                  navigate={cert_show_path(@org, @project, cert)}
                  class="text-primary hover:underline font-mono"
                >
                  {cert.name}
                </.link>
              </td>
              <td class="text-sm font-mono">{cert.domain}</td>
              <td class="flex items-center gap-1">
                <span class={["badge badge-xs", status_badge_class(cert.status)]}>
                  {cert.status}
                </span>
                <span
                  :if={cert.auto_renew && cert.acme_config != %{}}
                  class="badge badge-xs badge-info"
                >
                  ACME
                </span>
              </td>
              <td class="text-sm">
                {if cert.not_after, do: Calendar.strftime(cert.not_after, "%Y-%m-%d"), else: "—"}
              </td>
              <td class="text-sm">{cert.issuer || "—"}</td>
              <td class="text-sm text-base-content/60">
                {if cert.last_renewal_at,
                  do: Calendar.strftime(cert.last_renewal_at, "%Y-%m-%d %H:%M"),
                  else: "—"}
              </td>
              <td class="flex gap-1">
                <.link navigate={cert_show_path(@org, @project, cert)} class="btn btn-ghost btn-xs">
                  Details
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={cert.id}
                  data-confirm="Are you sure? Services using this certificate will lose their TLS reference."
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@certificates == []} class="text-center py-12 text-base-content/50">
          No certificates yet. Upload one to enable TLS termination.
        </div>
      </div>
    </div>
    """
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("expiring_soon"), do: "badge-warning"
  defp status_badge_class("expired"), do: "badge-error"
  defp status_badge_class("revoked"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-ghost"

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp cert_new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/new"

  defp cert_new_path(nil, project),
    do: ~p"/projects/#{project.slug}/certificates/new"

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/certificates/#{cert.id}"
end
