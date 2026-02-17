defmodule ZentinelCpWeb.InternalCaLive.IssueCertificate do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         ca when not is_nil(ca) <- Services.get_internal_ca(project.id) do
      {:ok,
       assign(socket,
         page_title: "Issue Certificate — #{project.name}",
         org: org,
         project: project,
         internal_ca: ca,
         form:
           to_form(%{
             "name" => "",
             "subject_cn" => "",
             "subject_ou" => "",
             "validity_days" => "365"
           })
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("issue", params, socket) do
    ca = socket.assigns.internal_ca
    project = socket.assigns.project
    org = socket.assigns.org

    validity_days =
      case Integer.parse(to_string(params["validity_days"] || "365")) do
        {n, _} -> n
        :error -> 365
      end

    attrs = Map.put(params, "validity_days", validity_days)

    case Services.issue_certificate(ca, attrs) do
      {:ok, cert} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "issue",
          "issued_certificate",
          cert.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Certificate issued (serial ##{cert.serial_number}).")
         |> push_navigate(to: cert_show_path(org, project, cert))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset))
         |> put_flash(:error, "Failed to issue certificate.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Issue Certificate"
        resource_type="issued_certificate"
        back_path={ca_path(@org, @project)}
      />

      <.k8s_section title="New Client Certificate">
        <form phx-submit="issue" class="space-y-4 max-w-lg">
          <div class="form-control">
            <label class="label"><span class="label-text">Name</span></label>
            <input
              type="text"
              name="name"
              value={@form[:name].value}
              required
              class="input input-bordered"
              placeholder="service-a-client"
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
              placeholder="service-a.example.com"
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Organization Unit (optional)</span></label>
            <input
              type="text"
              name="subject_ou"
              value={@form[:subject_ou].value}
              class="input input-bordered"
              placeholder="Engineering"
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Validity (days)</span></label>
            <input
              type="number"
              name="validity_days"
              value={@form[:validity_days].value}
              min="1"
              max="3650"
              class="input input-bordered"
            />
          </div>
          <button type="submit" class="btn btn-primary">Issue Certificate</button>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp ca_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/internal-ca"

  defp ca_path(nil, project),
    do: ~p"/projects/#{project.slug}/internal-ca"

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/internal-ca/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/internal-ca/certificates/#{cert.id}"
end
