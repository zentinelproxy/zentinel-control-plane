defmodule ZentinelCpWeb.PortalLive.Docs do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Portal, Projects.Project}
  import ZentinelCpWeb.PortalLive.Components

  @impl true
  def mount(%{"project_slug" => _slug} = params, _session, socket) do
    project = socket.assigns.portal_project
    specs = Portal.list_project_specs(project.id)

    {selected_spec, endpoints, schemas} =
      case params["spec_id"] do
        nil ->
          case specs do
            [first | _] ->
              eps = Portal.get_spec_paths(first)
              schemas = Portal.get_spec_schemas(first)
              {first, eps, schemas}

            [] ->
              {nil, [], %{}}
          end

        spec_id ->
          spec = Portal.get_spec(spec_id)

          if spec do
            eps = Portal.get_spec_paths(spec)
            schemas = Portal.get_spec_schemas(spec)
            {spec, eps, schemas}
          else
            {nil, [], %{}}
          end
      end

    grouped = Portal.group_paths_by_tag(endpoints)

    {:ok,
     assign(socket,
       page_title: "Docs — #{Project.portal_title(project)}",
       project: project,
       specs: specs,
       selected_spec: selected_spec,
       endpoints: endpoints,
       grouped_endpoints: grouped,
       schemas: schemas,
       selected_endpoint: nil
     ), layout: false}
  end

  @impl true
  def handle_event("select_endpoint", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    endpoint = Enum.at(socket.assigns.endpoints, idx)
    {:noreply, assign(socket, selected_endpoint: endpoint)}
  end

  @impl true
  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, selected_endpoint: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.portal_layout project={@project} current_path={"/portal/#{@project.slug}/docs"}>
      <div class="space-y-4">
        <h1 class="text-xl font-bold">API Documentation</h1>

        <div :if={@selected_spec == nil} class="text-base-content/50 py-8 text-center">
          No API specifications available.
        </div>

        <div :if={@selected_spec} class="grid grid-cols-1 lg:grid-cols-4 gap-4">
          <div class="lg:col-span-1">
            <div class="sticky top-4 space-y-4">
              <div class="text-sm font-bold text-base-content/50 uppercase">Endpoints</div>
              <div :for={{tag, endpoints} <- @grouped_endpoints} class="space-y-1">
                <div class="text-xs font-semibold text-base-content/40 uppercase mt-3">{tag}</div>
                <button
                  :for={{ep, idx} <- Enum.with_index(endpoints)}
                  phx-click="select_endpoint"
                  phx-value-index={find_global_index(@endpoints, ep)}
                  class={[
                    "w-full text-left px-2 py-1 rounded text-sm flex items-center gap-2 hover:bg-base-200",
                    @selected_endpoint == ep && "bg-base-200 font-semibold"
                  ]}
                >
                  <.method_badge method={ep.method} />
                  <span class="truncate font-mono text-xs">{ep.path}</span>
                </button>
              </div>
            </div>
          </div>

          <div class="lg:col-span-3">
            <div :if={@selected_endpoint == nil} class="text-base-content/50 py-8 text-center">
              Select an endpoint from the sidebar to view details.
            </div>

            <div :if={@selected_endpoint} class="space-y-4">
              <div class="flex items-center gap-3">
                <.method_badge method={@selected_endpoint.method} />
                <code class="text-lg font-mono">{@selected_endpoint.path}</code>
              </div>

              <p :if={@selected_endpoint.summary != ""} class="text-base-content/70">
                {@selected_endpoint.summary}
              </p>

              <p :if={@selected_endpoint.description != ""} class="text-sm text-base-content/60">
                {@selected_endpoint.description}
              </p>

              <div :if={@selected_endpoint.parameters != []} class="space-y-2">
                <h3 class="font-bold">Parameters</h3>
                <table class="table table-sm">
                  <thead class="bg-base-200">
                    <tr>
                      <th class="text-xs">Name</th>
                      <th class="text-xs">In</th>
                      <th class="text-xs">Required</th>
                      <th class="text-xs">Description</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={param <- @selected_endpoint.parameters}>
                      <td class="font-mono text-sm">{param["name"]}</td>
                      <td class="text-sm">{param["in"]}</td>
                      <td>
                        <span :if={param["required"]} class="badge badge-error badge-xs">
                          required
                        </span>
                      </td>
                      <td class="text-sm text-base-content/60">{param["description"]}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div :if={@selected_endpoint.request_body} class="space-y-2">
                <h3 class="font-bold">Request Body</h3>
                <pre class="bg-base-200 p-3 rounded text-sm overflow-x-auto"><code>{format_json(@selected_endpoint.request_body)}</code></pre>
              </div>

              <div :if={@selected_endpoint.responses != %{}} class="space-y-2">
                <h3 class="font-bold">Responses</h3>
                <div :for={{status, details} <- Enum.sort(@selected_endpoint.responses)} class="mb-3">
                  <div class="flex items-center gap-2 mb-1">
                    <span class={["badge badge-sm", status_color(status)]}>{status}</span>
                    <span class="text-sm text-base-content/60">{details["description"]}</span>
                  </div>
                  <pre
                    :if={details["content"]}
                    class="bg-base-200 p-3 rounded text-sm overflow-x-auto"
                  ><code>{format_json(details["content"])}</code></pre>
                </div>
              </div>

              <div class="space-y-2">
                <h3 class="font-bold">Example</h3>
                <pre class="bg-base-200 p-3 rounded text-sm overflow-x-auto"><code>{build_curl_example(@selected_endpoint)}</code></pre>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.portal_layout>
    """
  end

  defp find_global_index(all_endpoints, target) do
    Enum.find_index(all_endpoints, fn ep ->
      ep.path == target.path && ep.method == target.method
    end) || 0
  end

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(data), do: inspect(data)

  defp status_color(status) do
    code = if is_binary(status), do: String.to_integer(status), else: status

    cond do
      code >= 200 and code < 300 -> "badge-success"
      code >= 300 and code < 400 -> "badge-info"
      code >= 400 and code < 500 -> "badge-warning"
      code >= 500 -> "badge-error"
      true -> "badge-ghost"
    end
  rescue
    _ -> "badge-ghost"
  end

  defp build_curl_example(endpoint) do
    method = endpoint.method
    path = endpoint.path

    parts = ["curl -X #{method} \\"]
    parts = parts ++ ["  -H 'Authorization: Bearer YOUR_API_KEY' \\"]

    parts =
      if method in ["POST", "PUT", "PATCH"] do
        parts ++ ["  -H 'Content-Type: application/json' \\"]
      else
        parts
      end

    (parts ++ ["  'https://api.example.com#{path}'"])
    |> Enum.join("\n")
  end
end
