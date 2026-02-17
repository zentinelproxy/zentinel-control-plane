defmodule ZentinelCpWeb.MiddlewaresLive.Edit do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => middleware_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         middleware when not is_nil(middleware) <- Services.get_middleware(middleware_id),
         true <- middleware.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Middleware #{middleware.name} — #{project.name}",
         org: org,
         project: project,
         middleware: middleware,
         config_json: encode_config(middleware.config)
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("update_middleware", params, socket) do
    middleware = socket.assigns.middleware
    project = socket.assigns.project

    config = build_config(params["config"] || %{})

    attrs = %{
      name: params["name"],
      description: params["description"],
      config: config,
      enabled: params["enabled"] == "true"
    }

    case Services.update_middleware(middleware, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "middleware", updated.id,
          project_id: project.id
        )

        show_path = show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Middleware updated.")
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
      <h1 class="text-xl font-bold">Edit Middleware: {@middleware.name}</h1>

      <.k8s_section>
        <form phx-submit="update_middleware" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@middleware.name}
              required
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              rows="2"
              class="textarea textarea-bordered textarea-sm w-full"
            >{@middleware.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Type</span></label>
            <span class="badge badge-sm badge-outline">{@middleware.middleware_type}</span>
            <p class="text-xs text-base-content/50 mt-1">Type cannot be changed after creation.</p>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="enabled"
                value="true"
                checked={@middleware.enabled}
                class="checkbox checkbox-sm"
              />
              <span class="label-text font-medium">Enabled</span>
            </label>
          </div>

          <div class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Config (JSON)</span></label>
              <textarea
                name="config[_json]"
                rows="6"
                class="textarea textarea-bordered textarea-xs w-full font-mono"
              >{@config_json}</textarea>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={show_path(@org, @project, @middleware)} class="btn btn-ghost btn-sm">
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

  defp show_path(%{slug: org_slug}, project, mw),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/middlewares/#{mw.id}"

  defp show_path(nil, project, mw),
    do: ~p"/projects/#{project.slug}/middlewares/#{mw.id}"

  defp encode_config(nil), do: "{}"
  defp encode_config(config) when config == %{}, do: "{}"
  defp encode_config(config), do: Jason.encode!(config, pretty: true)

  defp build_config(%{"_json" => json}) when is_binary(json) and json != "" do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp build_config(params) when is_map(params) do
    params
    |> Map.drop(["_json"])
    |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end)
    |> Map.new()
  end

  defp build_config(_), do: %{}
end
