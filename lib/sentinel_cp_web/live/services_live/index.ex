defmodule SentinelCpWeb.ServicesLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Bundles, Orgs, Projects, Services}
  alias SentinelCp.Services.BundleIntegration

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "services:#{project.id}")
        end

        services = Services.list_services(project.id)
        {:ok, config} = Services.get_or_create_project_config(project.id)

        {:ok,
         assign(socket,
           page_title: "Services — #{project.name}",
           org: org,
           project: project,
           services: services,
           config: config,
           show_kdl_preview: false,
           kdl_preview: nil,
           show_generate: false,
           generate_version: suggest_next_version(project.id)
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project

    with service when not is_nil(service) <- Services.get_service(id),
         true <- service.project_id == project.id do
      case Services.delete_service(service) do
        {:ok, _} ->
          Audit.log_user_action(socket.assigns.current_user, "delete", "service", service.id,
            project_id: project.id
          )

          services = Services.list_services(project.id)

          {:noreply,
           socket
           |> assign(services: services)
           |> put_flash(:info, "Service deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete service.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Service not found.")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = socket.assigns.project

    with service when not is_nil(service) <- Services.get_service(id),
         true <- service.project_id == project.id do
      case Services.update_service(service, %{enabled: !service.enabled}) do
        {:ok, _} ->
          services = Services.list_services(project.id)
          {:noreply, assign(socket, services: services)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update service.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Service not found.")}
    end
  end

  @impl true
  def handle_event("preview_kdl", _, socket) do
    project = socket.assigns.project

    case BundleIntegration.preview_kdl(project.id) do
      {:ok, kdl} ->
        {:noreply, assign(socket, show_kdl_preview: true, kdl_preview: kdl)}

      {:error, :no_services} ->
        {:noreply, put_flash(socket, :error, "No enabled services to generate KDL from.")}
    end
  end

  @impl true
  def handle_event("close_preview", _, socket) do
    {:noreply, assign(socket, show_kdl_preview: false, kdl_preview: nil)}
  end

  @impl true
  def handle_event("show_generate", _, socket) do
    {:noreply, assign(socket, show_generate: true)}
  end

  @impl true
  def handle_event("close_generate", _, socket) do
    {:noreply, assign(socket, show_generate: false)}
  end

  @impl true
  def handle_event("generate_bundle", %{"version" => version}, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    case BundleIntegration.create_bundle_from_services(project.id, version,
           created_by_id: user.id
         ) do
      {:ok, bundle} ->
        Audit.log_user_action(user, "create", "bundle", bundle.id,
          project_id: project.id,
          metadata: %{source: "services"}
        )

        show_path = bundle_show_path(socket.assigns.org, project, bundle)

        {:noreply,
         socket
         |> put_flash(:info, "Bundle created from services, compilation started.")
         |> push_navigate(to: show_path)}

      {:error, :no_services} ->
        {:noreply, put_flash(socket, :error, "No enabled services to generate bundle from.")}

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
  def handle_event("update_config", params, socket) do
    config = socket.assigns.config

    attrs = %{
      log_level: params["log_level"],
      metrics_port: parse_int(params["metrics_port"])
    }

    case Services.update_project_config(config, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(config: updated)
         |> put_flash(:info, "Settings updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update settings.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Services</h1>
        </:filters>
        <:actions>
          <button phx-click="preview_kdl" class="btn btn-outline btn-sm">
            Preview KDL
          </button>
          <button phx-click="show_generate" class="btn btn-outline btn-sm">
            Generate Bundle
          </button>
          <.link navigate={openapi_import_path(@org, @project)} class="btn btn-outline btn-sm">
            Import from OpenAPI
          </.link>
          <.link navigate={service_new_path(@org, @project)} class="btn btn-primary btn-sm">
            New Service
          </.link>
        </:actions>
      </.table_toolbar>

      <%!-- KDL Preview Modal --%>
      <div :if={@show_kdl_preview}>
        <.k8s_section title="KDL Preview">
          <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto max-h-96 overflow-y-auto">{@kdl_preview}</pre>
          <div class="mt-3">
            <button phx-click="close_preview" class="btn btn-ghost btn-sm">Close</button>
          </div>
        </.k8s_section>
      </div>

      <%!-- Generate Bundle Form --%>
      <div :if={@show_generate}>
        <.k8s_section title="Generate Bundle from Services">
          <form phx-submit="generate_bundle" class="flex items-end gap-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Version</span></label>
              <input
                type="text"
                name="version"
                value={@generate_version}
                required
                class="input input-bordered input-sm w-48"
                placeholder="e.g. 1.0.0"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Create & Compile</button>
            <button type="button" phx-click="close_generate" class="btn btn-ghost btn-sm">
              Cancel
            </button>
          </form>
        </.k8s_section>
      </div>

      <%!-- Global Settings --%>
      <.k8s_section title="Global Settings">
        <form phx-submit="update_config" class="flex flex-wrap items-end gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Log Level</span></label>
            <select name="log_level" class="select select-bordered select-sm w-32">
              <option
                :for={level <- ~w(trace debug info warn error)}
                value={level}
                selected={level == @config.log_level}
              >
                {level}
              </option>
            </select>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Metrics Port</span></label>
            <input
              type="number"
              name="metrics_port"
              value={@config.metrics_port}
              class="input input-bordered input-sm w-28"
              min="1"
              max="65535"
            />
          </div>
          <button type="submit" class="btn btn-sm btn-outline">Save Settings</button>
        </form>
      </.k8s_section>

      <%!-- Services Table --%>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Type</th>
              <th class="text-xs uppercase">Route Path</th>
              <th class="text-xs uppercase">Upstream / Response</th>
              <th class="text-xs uppercase">Enabled</th>
              <th class="text-xs uppercase">Created</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={service <- @services}>
              <td>
                <.link
                  navigate={service_show_path(@org, @project, service)}
                  class="flex items-center gap-2 text-primary hover:underline font-mono"
                >
                  <.resource_badge type="service" />
                  {service.name}
                </.link>
              </td>
              <td>
                <span class="badge badge-sm badge-outline">{service.service_type || "standard"}</span>
              </td>
              <td class="font-mono text-sm">{service.route_path}</td>
              <td class="text-sm">
                {if service.upstream_url,
                  do: service.upstream_url,
                  else: "respond #{service.respond_status}"}
              </td>
              <td>
                <input
                  type="checkbox"
                  class="toggle toggle-sm toggle-success"
                  checked={service.enabled}
                  phx-click="toggle_enabled"
                  phx-value-id={service.id}
                />
              </td>
              <td class="text-sm">{Calendar.strftime(service.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="flex gap-1">
                <.link
                  navigate={service_show_path(@org, @project, service)}
                  class="btn btn-ghost btn-xs"
                >
                  Details
                </.link>
                <.link
                  navigate={service_edit_path(@org, @project, service)}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={service.id}
                  data-confirm="Are you sure you want to delete this service?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@services == []} class="text-center py-12 text-base-content/50">
          No services yet. Create one to get started.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp openapi_import_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/openapi/import"

  defp openapi_import_path(nil, project),
    do: ~p"/projects/#{project.slug}/openapi/import"

  defp service_new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/new"

  defp service_new_path(nil, project),
    do: ~p"/projects/#{project.slug}/services/new"

  defp service_show_path(%{slug: org_slug}, project, service),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/#{service.id}"

  defp service_show_path(nil, project, service),
    do: ~p"/projects/#{project.slug}/services/#{service.id}"

  defp service_edit_path(%{slug: org_slug}, project, service),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/#{service.id}/edit"

  defp service_edit_path(nil, project, service),
    do: ~p"/projects/#{project.slug}/services/#{service.id}/edit"

  defp bundle_show_path(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp suggest_next_version(project_id) do
    case Bundles.list_bundles(project_id, limit: 1) do
      [latest | _] ->
        case Version.parse(latest.version) do
          {:ok, v} -> "#{v.major}.#{v.minor}.#{v.patch + 1}"
          :error -> "0.0.1"
        end

      [] ->
        "0.0.1"
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n
end
