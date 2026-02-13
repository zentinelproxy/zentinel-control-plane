defmodule SentinelCpWeb.CertificatesLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "Upload Certificate — #{project.name}",
           org: org,
           project: project,
           tab: "upload"
         )}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  @impl true
  def handle_event("request_acme", params, socket) do
    project = socket.assigns.project

    acme_config = %{
      "email" => params["email"],
      "directory_url" => params["directory_url"] || "https://acme-v02.api.letsencrypt.org/directory"
    }

    # Create a placeholder certificate record with auto_renew enabled
    # The renewal system will issue the actual certificate
    attrs = %{
      project_id: project.id,
      name: params["name"] || params["domain"],
      domain: params["domain"],
      auto_renew: true,
      acme_config: acme_config
    }

    # We need cert_pem and key_pem for initial creation, so we trigger immediate issuance
    # First, create a minimal record, then trigger renewal
    alias SentinelCp.Services.Acme.Renewal
    alias SentinelCp.Services.Acme.Crypto

    # Generate a temporary self-signed cert to bootstrap the record
    cert_key = Crypto.generate_cert_key()
    key_pem = Crypto.private_key_to_pem(cert_key)

    case generate_self_signed(params["domain"], cert_key) do
      {:ok, cert_pem} ->
        create_attrs = Map.merge(attrs, %{cert_pem: cert_pem, key_pem: key_pem})

        case Services.create_certificate(create_attrs) do
          {:ok, cert} ->
            Audit.log_user_action(socket.assigns.current_user, "create", "certificate", cert.id,
              project_id: project.id,
              metadata: %{method: "acme_request"}
            )

            # Trigger immediate ACME issuance in background
            Task.start(fn -> Renewal.renew(cert) end)

            show_path = cert_show_path(socket.assigns.org, project, cert)

            {:noreply,
             socket
             |> put_flash(:info, "Certificate created. ACME issuance in progress...")
             |> push_navigate(to: show_path)}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

            {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate bootstrap cert: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_certificate", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      domain: params["domain"],
      cert_pem: params["cert_pem"],
      key_pem: params["key_pem"],
      ca_chain_pem: blank_to_nil(params["ca_chain_pem"]),
      auto_renew: params["auto_renew"] == "true"
    }

    case Services.create_certificate(attrs) do
      {:ok, cert} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "certificate", cert.id,
          project_id: project.id
        )

        show_path = cert_show_path(socket.assigns.org, project, cert)

        {:noreply,
         socket
         |> put_flash(:info, "Certificate uploaded.")
         |> push_navigate(to: show_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">New Certificate</h1>

      <div role="tablist" class="tabs tabs-bordered">
        <button
          role="tab"
          class={["tab", @tab == "upload" && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="upload"
        >
          Upload Certificate
        </button>
        <button
          role="tab"
          class={["tab", @tab == "acme" && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="acme"
        >
          Request via ACME
        </button>
      </div>

      <.k8s_section :if={@tab == "acme"}>
        <form phx-submit="request_acme" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Domain</span></label>
            <input
              type="text"
              name="domain"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. api.example.com"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name (optional)</span></label>
            <input
              type="text"
              name="name"
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API TLS Cert (defaults to domain)"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Email</span></label>
            <input
              type="email"
              name="email"
              required
              class="input input-bordered input-sm w-full"
              placeholder="admin@example.com"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Contact email for Let's Encrypt notifications</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Environment</span></label>
            <select name="directory_url" class="select select-bordered select-sm w-full">
              <option value="https://acme-staging-v02.api.letsencrypt.org/directory">
                Staging (testing)
              </option>
              <option value="https://acme-v02.api.letsencrypt.org/directory">
                Production
              </option>
            </select>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Request Certificate</button>
            <.link navigate={certs_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>

      <.k8s_section :if={@tab == "upload"}>
        <form phx-submit="create_certificate" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API TLS Cert"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Domain</span></label>
            <input
              type="text"
              name="domain"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. api.example.com"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Primary domain for this certificate (also extracted from PEM)</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Certificate PEM</span></label>
            <textarea
              name="cert_pem"
              required
              rows="8"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Private Key PEM</span></label>
            <textarea
              name="key_pem"
              required
              rows="8"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN PRIVATE KEY-----&#10;...&#10;-----END PRIVATE KEY-----"
            ></textarea>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                The private key is encrypted at rest and never leaves the control plane in plaintext.
              </span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">CA Chain PEM (optional)</span></label>
            <textarea
              name="ca_chain_pem"
              rows="6"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input type="checkbox" name="auto_renew" value="true" class="checkbox checkbox-sm" />
              <span class="label-text font-medium">Enable Auto-Renew</span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Upload Certificate</button>
            <.link navigate={certs_path(@org, @project)} class="btn btn-ghost btn-sm">
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

  defp certs_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates"

  defp certs_path(nil, project),
    do: ~p"/projects/#{project.slug}/certificates"

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/certificates/#{cert.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str

  # Generate a temporary self-signed certificate for bootstrapping ACME records
  defp generate_self_signed(domain, private_key) do
    subject = {:rdnSequence, [[{:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, domain}}]]}
    modulus = elem(private_key, 2)
    pub_exp = elem(private_key, 3)

    spki_algo = {:AlgorithmIdentifier, {1, 2, 840, 113549, 1, 1, 1}, <<5, 0>>}
    pub_key_der = :public_key.der_encode(:RSAPublicKey, {:RSAPublicKey, modulus, pub_exp})
    spki = {:SubjectPublicKeyInfo, spki_algo, pub_key_der}

    now = DateTime.utc_now()
    not_before = Calendar.strftime(now, "%y%m%d%H%M%SZ") |> to_charlist()

    not_after =
      DateTime.add(now, 86_400, :second)
      |> Calendar.strftime("%y%m%d%H%M%SZ")
      |> to_charlist()

    validity = {:Validity, {:utcTime, not_before}, {:utcTime, not_after}}
    serial = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()
    sig_algo = {:AlgorithmIdentifier, {1, 2, 840, 113549, 1, 1, 11}, <<5, 0>>}

    tbs =
      {:TBSCertificate, :v3, serial, sig_algo, subject, validity, subject, spki,
       :asn1_NOVALUE, :asn1_NOVALUE, :asn1_NOVALUE}

    tbs_der = :public_key.der_encode(:TBSCertificate, tbs)
    signature = :public_key.sign(tbs_der, :sha256, private_key)

    cert = {:Certificate, tbs, sig_algo, signature}
    cert_der = :public_key.der_encode(:Certificate, cert)
    pem = :public_key.pem_encode([{:Certificate, cert_der, :not_encrypted}])
    {:ok, pem}
  rescue
    e -> {:error, Exception.message(e)}
  end
end
