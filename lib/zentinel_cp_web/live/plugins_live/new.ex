defmodule ZentinelCpWeb.PluginsLive.New do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Plugins, Projects}
  alias ZentinelCp.Plugins.Plugin

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New Plugin — #{project.name}",
           org: org,
           project: project,
           plugin_types: Plugin.plugin_types(),
           selected_type: "wasm"
         )}
    end
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_type: type)}
  end

  @impl true
  def handle_event("create_plugin", params, socket) do
    project = socket.assigns.project

    config_schema = build_config(params["config_schema"] || %{})
    default_config = build_config(params["default_config"] || %{})

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      plugin_type: params["plugin_type"],
      config_schema: config_schema,
      default_config: default_config,
      enabled: params["enabled"] == "true",
      public: params["public"] == "true",
      author: params["author"]
    }

    case Plugins.create_plugin(attrs) do
      {:ok, plugin} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "plugin", plugin.id,
          project_id: project.id
        )

        show_path = show_path(socket.assigns.org, project, plugin)

        {:noreply,
         socket
         |> put_flash(:info, "Plugin created.")
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
      <h1 class="text-xl font-bold">Create Plugin</h1>

      <.k8s_section>
        <form phx-submit="create_plugin" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. Auth Validator"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              rows="2"
              class="textarea textarea-bordered textarea-sm w-full"
              placeholder="Optional description"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Author</span></label>
            <input
              type="text"
              name="author"
              class="input input-bordered input-sm w-full"
              placeholder="Optional author name"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Type</span></label>
            <select
              name="plugin_type"
              phx-change="select_type"
              phx-value-type=""
              class="select select-bordered select-sm w-48"
            >
              <option :for={t <- @plugin_types} value={t} selected={t == @selected_type}>{t}</option>
            </select>
          </div>

          <div class="flex gap-4">
            <div class="form-control">
              <label class="label cursor-pointer gap-2 justify-start">
                <input
                  type="checkbox"
                  name="enabled"
                  value="true"
                  checked
                  class="checkbox checkbox-sm"
                />
                <span class="label-text font-medium">Enabled</span>
              </label>
            </div>

            <div class="form-control">
              <label class="label cursor-pointer gap-2 justify-start">
                <input type="checkbox" name="public" value="true" class="checkbox checkbox-sm" />
                <span class="label-text font-medium">Public (marketplace)</span>
              </label>
            </div>
          </div>

          <div class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Config Schema (JSON)</p>
            <div class="form-control">
              <textarea
                name="config_schema[_json]"
                rows="4"
                class="textarea textarea-bordered textarea-xs w-full font-mono"
                placeholder={"{\n  \"type\": \"object\"\n}"}
              ></textarea>
            </div>
          </div>

          <div class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Default Config (JSON)</p>
            <div class="form-control">
              <textarea
                name="default_config[_json]"
                rows="4"
                class="textarea textarea-bordered textarea-xs w-full font-mono"
                placeholder={"{\n  \"key\": \"value\"\n}"}
              ></textarea>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Plugin</button>
            <.link navigate={index_path(@org, @project)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/plugins"

  defp show_path(%{slug: org_slug}, project, plugin),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/plugins/#{plugin.id}"

  defp show_path(nil, project, plugin),
    do: ~p"/projects/#{project.slug}/plugins/#{plugin.id}"

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
