defmodule SentinelCpWeb.CertificatesLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}
  alias SentinelCp.Services.Acme.Renewal

  @impl true
  def mount(%{"project_slug" => slug, "id" => cert_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         cert when not is_nil(cert) <- Services.get_certificate(cert_id),
         true <- cert.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Certificate #{cert.name} — #{project.name}",
         org: org,
         project: project,
         certificate: cert
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    cert = socket.assigns.certificate
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_certificate(cert) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "certificate", cert.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Certificate deleted.")
         |> push_navigate(to: certs_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete certificate.")}
    end
  end

  @impl true
  def handle_event("renew_now", _, socket) do
    cert = socket.assigns.certificate
    project = socket.assigns.project

    case Renewal.renew(cert) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "renew", "certificate", cert.id,
          project_id: project.id,
          metadata: %{method: "acme_manual"}
        )

        {:noreply,
         socket
         |> assign(certificate: updated)
         |> put_flash(:info, "Certificate renewed via ACME.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "ACME renewal failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@certificate.name}
        resource_type="certificate"
        back_path={certs_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", status_badge_class(@certificate.status)]}>
            {@certificate.status}
          </span>
        </:badge>
        <:action>
          <button
            :if={@certificate.auto_renew && @certificate.acme_config != %{}}
            phx-click="renew_now"
            data-confirm="Trigger ACME renewal now?"
            class="btn btn-info btn-sm"
          >
            Renew Now
          </button>
          <.link
            navigate={cert_edit_path(@org, @project, @certificate)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this certificate?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Certificate Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@certificate.id}</span></:item>
            <:item label="Name">{@certificate.name}</:item>
            <:item label="Slug"><span class="font-mono">{@certificate.slug}</span></:item>
            <:item label="Domain"><span class="font-mono">{@certificate.domain}</span></:item>
            <:item label="SAN Domains">
              {if @certificate.san_domains && @certificate.san_domains != [],
                do: Enum.join(@certificate.san_domains, ", "),
                else: "—"}
            </:item>
            <:item label="Issuer">{@certificate.issuer || "—"}</:item>
            <:item label="Fingerprint (SHA-256)">
              <span class="font-mono text-xs">{@certificate.fingerprint_sha256 || "—"}</span>
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Validity & Settings">
          <.definition_list>
            <:item label="Not Before">
              {if @certificate.not_before,
                do: Calendar.strftime(@certificate.not_before, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Not After">
              {if @certificate.not_after,
                do: Calendar.strftime(@certificate.not_after, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Status">
              <span class={["badge badge-sm", status_badge_class(@certificate.status)]}>
                {@certificate.status}
              </span>
            </:item>
            <:item label="Auto-Renew">
              {if @certificate.auto_renew, do: "Enabled", else: "Disabled"}
            </:item>
            <:item label="ACME Config">{format_map(@certificate.acme_config)}</:item>
            <:item label="Last Renewal">
              {if @certificate.last_renewal_at,
                do: Calendar.strftime(@certificate.last_renewal_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Last Renewal Error">
              <span :if={@certificate.last_renewal_error} class="text-error text-sm">
                {@certificate.last_renewal_error}
              </span>
              <span :if={!@certificate.last_renewal_error}>—</span>
            </:item>
            <:item label="Created">
              {Calendar.strftime(@certificate.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <div class="lg:col-span-2">
          <.k8s_section title="Certificate PEM">
            <pre class="bg-base-300 p-4 rounded text-xs font-mono whitespace-pre-wrap overflow-x-auto max-h-64 overflow-y-auto">{@certificate.cert_pem}</pre>
          </.k8s_section>
        </div>

        <div :if={@certificate.ca_chain_pem} class="lg:col-span-2">
          <.k8s_section title="CA Chain PEM">
            <pre class="bg-base-300 p-4 rounded text-xs font-mono whitespace-pre-wrap overflow-x-auto max-h-64 overflow-y-auto">{@certificate.ca_chain_pem}</pre>
          </.k8s_section>
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

  defp certs_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates"

  defp certs_path(nil, project),
    do: ~p"/projects/#{project.slug}/certificates"

  defp cert_edit_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/#{cert.id}/edit"

  defp cert_edit_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/certificates/#{cert.id}/edit"

  defp format_map(nil), do: "—"
  defp format_map(map) when map == %{}, do: "—"

  defp format_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end
end
