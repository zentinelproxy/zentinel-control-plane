defmodule SentinelCpWeb.PortalLive.Console do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Portal, Projects.Project}
  import SentinelCpWeb.PortalLive.Components

  @impl true
  def mount(%{"project_slug" => _slug}, _session, socket) do
    project = socket.assigns.portal_project

    {:ok,
     assign(socket,
       page_title: "Console — #{Project.portal_title(project)}",
       project: project,
       method: "GET",
       url: "",
       headers: [%{key: "", value: ""}],
       body: "",
       api_key: "",
       response: nil,
       curl_command: nil,
       loading: false
     ), layout: false}
  end

  @impl true
  def handle_event("update_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, method: method)}
  end

  @impl true
  def handle_event("update_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, url: url)}
  end

  @impl true
  def handle_event("update_body", %{"body" => body}, socket) do
    {:noreply, assign(socket, body: body)}
  end

  @impl true
  def handle_event("update_api_key", %{"api_key" => key}, socket) do
    {:noreply, assign(socket, api_key: key)}
  end

  @impl true
  def handle_event("add_header", _, socket) do
    headers = socket.assigns.headers ++ [%{key: "", value: ""}]
    {:noreply, assign(socket, headers: headers)}
  end

  @impl true
  def handle_event("remove_header", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    headers = List.delete_at(socket.assigns.headers, idx)
    headers = if headers == [], do: [%{key: "", value: ""}], else: headers
    {:noreply, assign(socket, headers: headers)}
  end

  @impl true
  def handle_event("update_header", %{"index" => index, "field" => field, "value" => value}, socket) do
    idx = String.to_integer(index)

    headers =
      List.update_at(socket.assigns.headers, idx, fn h ->
        Map.put(h, String.to_existing_atom(field), value)
      end)

    {:noreply, assign(socket, headers: headers)}
  end

  @impl true
  def handle_event("send_request", _, socket) do
    url = socket.assigns.url

    if url == "" do
      {:noreply, put_flash(socket, :error, "URL is required.")}
    else
      headers =
        socket.assigns.headers
        |> Enum.reject(fn h -> h.key == "" end)
        |> Enum.map(fn h -> {h.key, h.value} end)

      headers =
        if socket.assigns.api_key != "" do
          [{"Authorization", "Bearer #{socket.assigns.api_key}"} | headers]
        else
          headers
        end

      body = if socket.assigns.body != "", do: socket.assigns.body, else: nil

      curl = Portal.build_curl_command(socket.assigns.method, url, headers, body)
      socket = assign(socket, loading: true, curl_command: curl)

      # Execute request asynchronously
      send(self(), {:execute_request, socket.assigns.method, url, headers, body})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:execute_request, method, url, headers, body}, socket) do
    response =
      case Portal.execute_request(method, url, headers, body) do
        {:ok, resp} -> resp
        {:error, reason} -> %{status: 0, headers: [], body: reason, duration_ms: 0}
      end

    {:noreply, assign(socket, response: response, loading: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.portal_layout project={@project} current_path={"/portal/#{@project.slug}/console"}>
      <div class="space-y-4">
        <h1 class="text-xl font-bold">API Console</h1>

        <div class="card bg-base-200 p-4 space-y-4">
          <div class="flex gap-2">
            <select
              class="select select-bordered select-sm w-28"
              phx-change="update_method"
              name="method"
            >
              <option :for={m <- ~w(GET POST PUT PATCH DELETE)} selected={m == @method} value={m}>
                {m}
              </option>
            </select>
            <input
              type="text"
              class="input input-bordered input-sm flex-1"
              placeholder="https://api.example.com/v1/endpoint"
              value={@url}
              phx-blur="update_url"
              phx-keyup="update_url"
              name="url"
            />
            <button
              class={["btn btn-primary btn-sm", @loading && "loading"]}
              phx-click="send_request"
              disabled={@loading}
            >
              Send
            </button>
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-sm font-bold">Headers</span>
              <button class="btn btn-ghost btn-xs" phx-click="add_header">+ Add</button>
            </div>
            <div :for={{header, idx} <- Enum.with_index(@headers)} class="flex gap-2">
              <input
                type="text"
                class="input input-bordered input-sm flex-1"
                placeholder="Key"
                value={header.key}
                phx-blur="update_header"
                phx-value-index={idx}
                phx-value-field="key"
                name={"header_key_#{idx}"}
              />
              <input
                type="text"
                class="input input-bordered input-sm flex-1"
                placeholder="Value"
                value={header.value}
                phx-blur="update_header"
                phx-value-index={idx}
                phx-value-field="value"
                name={"header_value_#{idx}"}
              />
              <button class="btn btn-ghost btn-xs" phx-click="remove_header" phx-value-index={idx}>
                x
              </button>
            </div>
          </div>

          <div :if={@method in ~w(POST PUT PATCH)} class="space-y-2">
            <span class="text-sm font-bold">Body</span>
            <textarea
              class="textarea textarea-bordered w-full font-mono text-sm"
              rows="5"
              placeholder='{"key": "value"}'
              phx-blur="update_body"
              name="body"
            >{@body}</textarea>
          </div>

          <div class="space-y-2">
            <span class="text-sm font-bold">API Key</span>
            <input
              type="password"
              class="input input-bordered input-sm w-full"
              placeholder="Paste your API key (added as Authorization: Bearer header)"
              value={@api_key}
              phx-blur="update_api_key"
              name="api_key"
            />
          </div>
        </div>

        <div :if={@curl_command} class="space-y-2">
          <span class="text-sm font-bold">cURL</span>
          <pre class="bg-base-200 p-3 rounded text-sm overflow-x-auto"><code>{@curl_command}</code></pre>
        </div>

        <div :if={@response} class="space-y-2">
          <div class="flex items-center gap-3">
            <span class="text-sm font-bold">Response</span>
            <span class={["badge badge-sm", response_color(@response.status)]}>
              {@response.status}
            </span>
            <span class="text-xs text-base-content/50">{@response.duration_ms}ms</span>
          </div>

          <div :if={@response.headers != []} class="collapse collapse-arrow bg-base-200">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-medium">
              Response Headers ({length(@response.headers)})
            </div>
            <div class="collapse-content">
              <div :for={{k, v} <- @response.headers} class="text-xs font-mono py-0.5">
                <span class="text-base-content/50">{k}:</span> {v}
              </div>
            </div>
          </div>

          <pre class="bg-base-200 p-3 rounded text-sm overflow-x-auto max-h-96"><code>{@response.body}</code></pre>
        </div>
      </div>
    </.portal_layout>
    """
  end

  defp response_color(status) when status >= 200 and status < 300, do: "badge-success"
  defp response_color(status) when status >= 300 and status < 400, do: "badge-info"
  defp response_color(status) when status >= 400 and status < 500, do: "badge-warning"
  defp response_color(status) when status >= 500, do: "badge-error"
  defp response_color(_), do: "badge-ghost"
end
