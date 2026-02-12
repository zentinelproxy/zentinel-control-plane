defmodule SentinelCpWeb.ServiceTemplatesLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Services}
  alias SentinelCp.Services.ServiceTemplate

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New Template — #{project.name}",
           org: org,
           project: project
         )}
    end
  end

  @impl true
  def handle_event("create_template", params, socket) do
    project = socket.assigns.project

    template_data =
      %{}
      |> maybe_put_string("route_path", params["route_path"])
      |> maybe_put_string("upstream_url", params["upstream_url"])
      |> maybe_put_int("respond_status", params["respond_status"])
      |> maybe_put_string("respond_body", params["respond_body"])
      |> maybe_put_int("timeout_seconds", params["timeout_seconds"])

    attrs = %{
      name: params["name"],
      description: params["description"],
      category: params["category"],
      template_data: template_data,
      project_id: project.id
    }

    case Services.create_template(attrs) do
      {:ok, template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template created.")
         |> push_navigate(to: template_show_path(socket.assigns.org, project, template))}

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
      <h1 class="text-xl font-bold">Create Service Template</h1>

      <.k8s_section>
        <form phx-submit="create_template" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input type="text" name="name" required class="input input-bordered input-sm w-full" placeholder="e.g. REST API" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea name="description" rows="2" class="textarea textarea-bordered textarea-sm w-full" placeholder="Template description"></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Category</span></label>
            <select name="category" required class="select select-bordered select-sm w-48">
              <option :for={cat <- ServiceTemplate.categories()} value={cat}>{String.capitalize(cat)}</option>
            </select>
          </div>

          <div class="divider text-xs text-base-content/50">Template Defaults</div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Route Path</span></label>
            <input type="text" name="route_path" class="input input-bordered input-xs w-full" placeholder="/api/*" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Upstream URL</span></label>
            <input type="text" name="upstream_url" class="input input-bordered input-xs w-full" placeholder="http://backend:8080" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Response Status</span></label>
              <input type="number" name="respond_status" class="input input-bordered input-xs w-24" placeholder="200" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Timeout (seconds)</span></label>
              <input type="number" name="timeout_seconds" class="input input-bordered input-xs w-24" placeholder="30" />
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Response Body</span></label>
            <textarea name="respond_body" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="OK"></textarea>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Template</button>
            <.link navigate={templates_path(@org, @project)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp templates_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates"

  defp templates_path(nil, project),
    do: ~p"/projects/#{project.slug}/service-templates"

  defp template_show_path(%{slug: org_slug}, project, template),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates/#{template.id}"

  defp template_show_path(nil, project, template),
    do: ~p"/projects/#{project.slug}/service-templates/#{template.id}"

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, _key, ""), do: map
  defp maybe_put_string(map, key, val), do: Map.put(map, key, val)

  defp maybe_put_int(map, _key, nil), do: map
  defp maybe_put_int(map, _key, ""), do: map

  defp maybe_put_int(map, key, val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> Map.put(map, key, n)
      :error -> map
    end
  end

  defp maybe_put_int(map, key, val) when is_integer(val), do: Map.put(map, key, val)
end
