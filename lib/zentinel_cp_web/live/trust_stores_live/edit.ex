defmodule ZentinelCpWeb.TrustStoresLive.Edit do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => ts_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         ts when not is_nil(ts) <- Services.get_trust_store(ts_id),
         true <- ts.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Trust Store — #{ts.name}",
         org: org,
         project: project,
         trust_store: ts
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("update_trust_store", params, socket) do
    ts = socket.assigns.trust_store
    project = socket.assigns.project

    attrs = %{
      name: params["name"],
      description: blank_to_nil(params["description"]),
      certificates_pem: params["certificates_pem"]
    }

    case Services.update_trust_store(ts, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "trust_store", ts.id,
          project_id: project.id
        )

        show_path = ts_show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Trust store updated.")
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
      <h1 class="text-xl font-bold">Edit Trust Store: {@trust_store.name}</h1>

      <.k8s_section>
        <form phx-submit="update_trust_store" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              value={@trust_store.name}
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Description (optional)</span>
            </label>
            <textarea
              name="description"
              rows="2"
              class="textarea textarea-bordered textarea-sm w-full"
            >{@trust_store.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">CA Certificates PEM</span>
            </label>
            <textarea
              name="certificates_pem"
              required
              rows="10"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
            >{@trust_store.certificates_pem}</textarea>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Paste one or more CA certificates in PEM format. Metadata will be re-extracted on save.
              </span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={ts_show_path(@org, @project, @trust_store)} class="btn btn-ghost btn-sm">
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

  defp ts_show_path(%{slug: org_slug}, project, ts),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/trust-stores/#{ts.id}"

  defp ts_show_path(nil, project, ts),
    do: ~p"/projects/#{project.slug}/trust-stores/#{ts.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str
end
