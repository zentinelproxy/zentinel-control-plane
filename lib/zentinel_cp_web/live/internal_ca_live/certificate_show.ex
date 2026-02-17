defmodule ZentinelCpWeb.InternalCaLive.CertificateShow do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => cert_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         ca when not is_nil(ca) <- Services.get_internal_ca(project.id),
         cert when not is_nil(cert) <- Services.get_issued_certificate(cert_id),
         true <- cert.internal_ca_id == ca.id do
      {:ok,
       assign(socket,
         page_title: "Certificate #{cert.name} — #{project.name}",
         org: org,
         project: project,
         internal_ca: ca,
         certificate: cert
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("revoke", _, socket) do
    cert = socket.assigns.certificate
    project = socket.assigns.project

    case Services.revoke_issued_certificate(cert) do
      {:ok, revoked} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "revoke",
          "issued_certificate",
          cert.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> assign(certificate: revoked)
         |> put_flash(:info, "Certificate revoked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke certificate.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@certificate.name}
        resource_type="issued_certificate"
        back_path={ca_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", status_class(@certificate.status)]}>
            {@certificate.status}
          </span>
        </:badge>
        <:action>
          <button
            :if={@certificate.status == "active"}
            phx-click="revoke"
            data-confirm="Are you sure you want to revoke this certificate?"
            class="btn btn-error btn-sm"
          >
            Revoke
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Certificate Details">
          <.definition_list>
            <:item label="Name">{@certificate.name}</:item>
            <:item label="Serial Number">{@certificate.serial_number}</:item>
            <:item label="Subject CN"><span class="font-mono">{@certificate.subject_cn}</span></:item>
            <:item label="Subject OU">{@certificate.subject_ou || "—"}</:item>
            <:item label="Fingerprint (SHA-256)">
              <span class="font-mono text-xs">{@certificate.fingerprint_sha256 || "—"}</span>
            </:item>
            <:item label="Key Usage">{@certificate.key_usage}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Validity & Status">
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
              <span class={["badge badge-sm", status_class(@certificate.status)]}>
                {@certificate.status}
              </span>
            </:item>
            <:item label="Revoked At">
              {if @certificate.revoked_at,
                do: Calendar.strftime(@certificate.revoked_at, "%Y-%m-%d %H:%M:%S UTC"),
                else: "—"}
            </:item>
            <:item label="Revoke Reason">{@certificate.revoke_reason || "—"}</:item>
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
      </div>
    </div>
    """
  end

  defp status_class("active"), do: "badge-success"
  defp status_class("revoked"), do: "badge-error"
  defp status_class("expired"), do: "badge-warning"
  defp status_class(_), do: "badge-ghost"

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp ca_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/internal-ca"

  defp ca_path(nil, project),
    do: ~p"/projects/#{project.slug}/internal-ca"
end
