defmodule SentinelCpWeb.TrustStoresLive.New do
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
           page_title: "New Trust Store — #{project.name}",
           org: org,
           project: project
         )}
    end
  end

  @impl true
  def handle_event("create_trust_store", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: blank_to_nil(params["description"]),
      certificates_pem: params["certificates_pem"]
    }

    case Services.create_trust_store(attrs) do
      {:ok, ts} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "trust_store", ts.id,
          project_id: project.id
        )

        show_path = ts_show_path(socket.assigns.org, project, ts)

        {:noreply,
         socket
         |> put_flash(:info, "Trust store created.")
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
      <h1 class="text-xl font-bold">New Trust Store</h1>

      <.k8s_section>
        <form phx-submit="create_trust_store" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. Internal CA"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description (optional)</span></label>
            <textarea
              name="description"
              rows="2"
              class="textarea textarea-bordered textarea-sm w-full"
              placeholder="Optional description"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">CA Certificates PEM</span></label>
            <textarea
              name="certificates_pem"
              required
              rows="10"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
            ></textarea>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Paste one or more CA certificates in PEM format.
              </span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Trust Store</button>
            <.link navigate={ts_index_path(@org, @project)} class="btn btn-ghost btn-sm">
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

  defp ts_index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores"

  defp ts_index_path(nil, project),
    do: ~p"/projects/#{project.slug}/trust-stores"

  defp ts_show_path(%{slug: org_slug}, project, ts),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores/#{ts.id}"

  defp ts_show_path(nil, project, ts),
    do: ~p"/projects/#{project.slug}/trust-stores/#{ts.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str
end
