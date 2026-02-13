defmodule SentinelCpWeb.CertificatesLive.Edit do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => cert_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         cert when not is_nil(cert) <- Services.get_certificate(cert_id),
         true <- cert.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Certificate — #{cert.name}",
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
  def handle_event("update_certificate", params, socket) do
    cert = socket.assigns.certificate
    project = socket.assigns.project

    acme_config =
      %{}
      |> maybe_put_acme("email", params["acme_email"])
      |> maybe_put_acme("directory_url", params["acme_directory_url"])
      |> maybe_put_acme("renewal_days", params["acme_renewal_days"])

    attrs = %{
      name: params["name"],
      auto_renew: params["auto_renew"] == "true",
      acme_config: if(acme_config == %{}, do: cert.acme_config || %{}, else: acme_config),
      status: params["status"]
    }

    case Services.update_certificate(cert, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "certificate", cert.id,
          project_id: project.id
        )

        show_path = cert_show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Certificate updated.")
         |> push_navigate(to: show_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">Edit Certificate</h1>

      <.k8s_section>
        <form phx-submit="update_certificate" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              value={@certificate.name}
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Domain</span></label>
            <input
              type="text"
              disabled
              value={@certificate.domain}
              class="input input-bordered input-sm w-full input-disabled"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Domain cannot be changed. Upload a new certificate instead.</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Status</span></label>
            <select name="status" class="select select-bordered select-sm w-48">
              <option value="active" selected={@certificate.status == "active"}>Active</option>
              <option value="expiring_soon" selected={@certificate.status == "expiring_soon"}>Expiring Soon</option>
              <option value="expired" selected={@certificate.status == "expired"}>Expired</option>
              <option value="revoked" selected={@certificate.status == "revoked"}>Revoked</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="auto_renew"
                value="true"
                checked={@certificate.auto_renew}
                class="checkbox checkbox-sm"
              />
              <span class="label-text font-medium">Enable Auto-Renew (ACME)</span>
            </label>
          </div>

          <div class="divider text-sm text-base-content/50">ACME Configuration</div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">ACME Email</span></label>
            <input
              type="email"
              name="acme_email"
              value={(@certificate.acme_config || %{})["email"]}
              class="input input-bordered input-sm w-full"
              placeholder="admin@example.com"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Contact email for Let's Encrypt notifications</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">ACME Directory</span></label>
            <select name="acme_directory_url" class="select select-bordered select-sm w-full">
              <option
                value="https://acme-v02.api.letsencrypt.org/directory"
                selected={(@certificate.acme_config || %{})["directory_url"] == "https://acme-v02.api.letsencrypt.org/directory"}
              >
                Let's Encrypt Production
              </option>
              <option
                value="https://acme-staging-v02.api.letsencrypt.org/directory"
                selected={(@certificate.acme_config || %{})["directory_url"] == "https://acme-staging-v02.api.letsencrypt.org/directory"}
              >
                Let's Encrypt Staging
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Renewal Threshold (days)</span></label>
            <input
              type="number"
              name="acme_renewal_days"
              value={(@certificate.acme_config || %{})["renewal_days"] || "30"}
              min="1"
              max="90"
              class="input input-bordered input-sm w-32"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Renew when certificate expires within this many days</span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={cert_show_path(@org, @project, @certificate)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/certificates/#{cert.id}"

  defp maybe_put_acme(map, _key, nil), do: map
  defp maybe_put_acme(map, _key, ""), do: map
  defp maybe_put_acme(map, key, value), do: Map.put(map, key, value)
end
