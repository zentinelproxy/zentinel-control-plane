defmodule ZentinelCpWeb.InternalCaLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug) do
      internal_ca = Services.get_internal_ca(project.id)

      issued_certs =
        if internal_ca, do: Services.list_issued_certificates(internal_ca.id), else: []

      {:ok,
       assign(socket,
         page_title: "Internal CA — #{project.name}",
         org: org,
         project: project,
         internal_ca: internal_ca,
         issued_certificates: issued_certs,
         form:
           to_form(%{
             "name" => "",
             "subject_cn" => "",
             "key_algorithm" => "EC-P384",
             "validity_years" => "10"
           })
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("initialize", %{"name" => _, "subject_cn" => _} = params, socket) do
    project = socket.assigns.project

    attrs =
      params
      |> Map.put("project_id", project.id)
      |> Map.update("validity_years", 10, fn v ->
        case Integer.parse(to_string(v)) do
          {n, _} -> n
          :error -> 10
        end
      end)

    case Services.initialize_internal_ca(attrs) do
      {:ok, ca} ->
        Audit.log_user_action(socket.assigns.current_user, "initialize", "internal_ca", ca.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> assign(internal_ca: ca, issued_certificates: [])
         |> put_flash(:info, "Internal CA initialized.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset))
         |> put_flash(:error, "Failed to initialize CA.")}
    end
  end

  @impl true
  def handle_event("destroy", _, socket) do
    ca = socket.assigns.internal_ca
    project = socket.assigns.project

    case Services.destroy_internal_ca(ca) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "destroy", "internal_ca", ca.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> assign(internal_ca: nil, issued_certificates: [])
         |> put_flash(:info, "Internal CA destroyed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not destroy CA.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Internal CA"
        resource_type="internal_ca"
        back_path={project_path(@org, @project)}
      >
        <:action>
          <.link
            :if={@internal_ca}
            navigate={issue_cert_path(@org, @project)}
            class="btn btn-primary btn-sm"
          >
            Issue Certificate
          </.link>
          <button
            :if={@internal_ca}
            phx-click="destroy"
            data-confirm="This will destroy the CA and revoke all issued certificates. Are you sure?"
            class="btn btn-error btn-sm"
          >
            Destroy CA
          </button>
        </:action>
      </.detail_header>

      <%= if @internal_ca do %>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.k8s_section title="CA Details">
            <.definition_list>
              <:item label="Name">{@internal_ca.name}</:item>
              <:item label="Algorithm">{@internal_ca.key_algorithm}</:item>
              <:item label="Subject CN">
                <span class="font-mono">{@internal_ca.subject_cn}</span>
              </:item>
              <:item label="Fingerprint (SHA-256)">
                <span class="font-mono text-xs">{@internal_ca.fingerprint_sha256 || "—"}</span>
              </:item>
              <:item label="Status">
                <span class={["badge badge-sm", ca_status_class(@internal_ca.status)]}>
                  {@internal_ca.status}
                </span>
              </:item>
            </.definition_list>
          </.k8s_section>

          <.k8s_section title="Validity">
            <.definition_list>
              <:item label="Not Before">
                {if @internal_ca.not_before,
                  do: Calendar.strftime(@internal_ca.not_before, "%Y-%m-%d %H:%M:%S UTC"),
                  else: "—"}
              </:item>
              <:item label="Not After">
                {if @internal_ca.not_after,
                  do: Calendar.strftime(@internal_ca.not_after, "%Y-%m-%d %H:%M:%S UTC"),
                  else: "—"}
              </:item>
              <:item label="Next Serial">{@internal_ca.next_serial}</:item>
              <:item label="CRL Updated">
                {if @internal_ca.crl_updated_at,
                  do: Calendar.strftime(@internal_ca.crl_updated_at, "%Y-%m-%d %H:%M:%S UTC"),
                  else: "—"}
              </:item>
            </.definition_list>
          </.k8s_section>
        </div>

        <.k8s_section title="Issued Certificates">
          <div :if={@issued_certificates == []} class="text-base-content/50 py-4">
            No certificates issued yet.
          </div>
          <table :if={@issued_certificates != []} class="table table-sm w-full">
            <thead>
              <tr>
                <th>Name</th>
                <th>Subject CN</th>
                <th>Serial</th>
                <th>Status</th>
                <th>Expires</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={cert <- @issued_certificates}>
                <td>{cert.name}</td>
                <td class="font-mono text-sm">{cert.subject_cn}</td>
                <td>{cert.serial_number}</td>
                <td>
                  <span class={["badge badge-sm", cert_status_class(cert.status)]}>
                    {cert.status}
                  </span>
                </td>
                <td>
                  {if cert.not_after,
                    do: Calendar.strftime(cert.not_after, "%Y-%m-%d"),
                    else: "—"}
                </td>
                <td>
                  <.link navigate={cert_show_path(@org, @project, cert)} class="btn btn-xs btn-ghost">
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </.k8s_section>
      <% else %>
        <.k8s_section title="Initialize Internal CA">
          <p class="mb-4 text-base-content/70">
            No internal CA has been configured for this project. Initialize one to
            issue client certificates for mutual TLS authentication.
          </p>
          <form phx-submit="initialize" class="space-y-4 max-w-lg">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                value={@form[:name].value}
                required
                class="input input-bordered"
                placeholder="My Project CA"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Subject CN</span></label>
              <input
                type="text"
                name="subject_cn"
                value={@form[:subject_cn].value}
                required
                class="input input-bordered"
                placeholder="My Project Internal CA"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Algorithm</span></label>
              <select name="key_algorithm" class="select select-bordered">
                <option value="EC-P384" selected={@form[:key_algorithm].value == "EC-P384"}>
                  EC P-384
                </option>
                <option value="RSA-2048" selected={@form[:key_algorithm].value == "RSA-2048"}>
                  RSA 2048
                </option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Validity (years)</span></label>
              <input
                type="number"
                name="validity_years"
                value={@form[:validity_years].value}
                min="1"
                max="30"
                class="input input-bordered"
              />
            </div>
            <button type="submit" class="btn btn-primary">Initialize CA</button>
          </form>
        </.k8s_section>
      <% end %>
    </div>
    """
  end

  defp ca_status_class("active"), do: "badge-success"
  defp ca_status_class("rotated"), do: "badge-warning"
  defp ca_status_class("destroyed"), do: "badge-error"
  defp ca_status_class(_), do: "badge-ghost"

  defp cert_status_class("active"), do: "badge-success"
  defp cert_status_class("revoked"), do: "badge-error"
  defp cert_status_class("expired"), do: "badge-warning"
  defp cert_status_class(_), do: "badge-ghost"

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp project_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

  defp issue_cert_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/internal-ca/certificates/new"

  defp issue_cert_path(nil, project),
    do: ~p"/projects/#{project.slug}/internal-ca/certificates/new"

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/internal-ca/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/internal-ca/certificates/#{cert.id}"
end
