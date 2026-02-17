defmodule ZentinelCpWeb.HealthChecksLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Projects, Rollouts}
  alias ZentinelCp.Rollouts.HealthChecker

  @methods ~w(GET POST HEAD)

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        endpoints = Rollouts.list_health_check_endpoints(project.id)

        {:ok,
         assign(socket,
           page_title: "Health Checks — #{project.name}",
           org: org,
           project: project,
           endpoints: endpoints,
           show_form: false,
           editing_endpoint: nil,
           test_results: %{},
           form: to_form(%{}, as: "endpoint"),
           methods: @methods
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply,
     assign(socket,
       show_form: !socket.assigns.show_form,
       editing_endpoint: nil,
       form: to_form(default_form_data(), as: "endpoint")
     )}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    endpoint = Rollouts.get_health_check_endpoint!(id)

    form_data = %{
      "name" => endpoint.name,
      "url" => endpoint.url,
      "method" => endpoint.method,
      "timeout_ms" => to_string(endpoint.timeout_ms),
      "expected_status" => to_string(endpoint.expected_status),
      "expected_body_contains" => endpoint.expected_body_contains || "",
      "headers" => format_headers(endpoint.headers),
      "enabled" => endpoint.enabled
    }

    {:noreply,
     assign(socket,
       show_form: true,
       editing_endpoint: endpoint,
       form: to_form(form_data, as: "endpoint")
     )}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       show_form: false,
       editing_endpoint: nil,
       form: to_form(%{}, as: "endpoint")
     )}
  end

  @impl true
  def handle_event("create_endpoint", %{"endpoint" => params}, socket) do
    project = socket.assigns.project

    attrs = build_endpoint_attrs(params, project.id)

    case Rollouts.create_health_check_endpoint(attrs) do
      {:ok, _endpoint} ->
        endpoints = Rollouts.list_health_check_endpoints(project.id)

        {:noreply,
         socket
         |> assign(endpoints: endpoints, show_form: false, form: to_form(%{}, as: "endpoint"))
         |> put_flash(:info, "Health check endpoint created successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "endpoint"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("update_endpoint", %{"endpoint" => params}, socket) do
    endpoint = socket.assigns.editing_endpoint
    attrs = build_endpoint_attrs(params, nil)

    case Rollouts.update_health_check_endpoint(endpoint, attrs) do
      {:ok, _endpoint} ->
        endpoints = Rollouts.list_health_check_endpoints(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(
           endpoints: endpoints,
           show_form: false,
           editing_endpoint: nil,
           form: to_form(%{}, as: "endpoint")
         )
         |> put_flash(:info, "Health check endpoint updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "endpoint"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    endpoint = Rollouts.get_health_check_endpoint!(id)

    case Rollouts.delete_health_check_endpoint(endpoint) do
      {:ok, _} ->
        endpoints = Rollouts.list_health_check_endpoints(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(endpoints: endpoints)
         |> put_flash(:info, "Health check endpoint deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete health check endpoint.")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    endpoint = Rollouts.get_health_check_endpoint!(id)

    case Rollouts.update_health_check_endpoint(endpoint, %{enabled: !endpoint.enabled}) do
      {:ok, _} ->
        endpoints = Rollouts.list_health_check_endpoints(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(endpoints: endpoints)
         |> put_flash(
           :info,
           "Health check #{if endpoint.enabled, do: "disabled", else: "enabled"}."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update health check.")}
    end
  end

  @impl true
  def handle_event("test", %{"id" => id}, socket) do
    endpoint = Rollouts.get_health_check_endpoint!(id)

    # Run the test in a task to avoid blocking
    test_results = Map.put(socket.assigns.test_results, id, :testing)
    socket = assign(socket, test_results: test_results)

    send(self(), {:run_test, endpoint})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:run_test, endpoint}, socket) do
    start_time = System.monotonic_time(:millisecond)
    result = HealthChecker.check(endpoint)
    latency = System.monotonic_time(:millisecond) - start_time

    test_results =
      case result do
        :pass ->
          Map.put(socket.assigns.test_results, endpoint.id, {:pass, latency})

        {:fail, reason} ->
          Map.put(socket.assigns.test_results, endpoint.id, {:fail, reason})
      end

    {:noreply, assign(socket, test_results: test_results)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Health Check Endpoints</h1>
        </:filters>
        <:actions>
          <.link navigate={rollouts_path(@org, @project)} class="btn btn-outline btn-sm">
            Back to Rollouts
          </.link>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Endpoint
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={if @editing_endpoint, do: "Edit Endpoint", else: "Create Endpoint"}>
          <form
            phx-submit={if @editing_endpoint, do: "update_endpoint", else: "create_endpoint"}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="endpoint[name]"
                  value={@form[:name].value}
                  required
                  maxlength="100"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. API Health"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Method</span></label>
                <select name="endpoint[method]" class="select select-bordered select-sm w-full">
                  <option
                    :for={method <- @methods}
                    value={method}
                    selected={@form[:method].value == method}
                  >
                    {method}
                  </option>
                </select>
              </div>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">URL *</span></label>
              <input
                type="url"
                name="endpoint[url]"
                value={@form[:url].value}
                required
                class="input input-bordered input-sm w-full"
                placeholder="https://example.com/health"
              />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Timeout (ms)</span></label>
                <input
                  type="number"
                  name="endpoint[timeout_ms]"
                  value={@form[:timeout_ms].value || "5000"}
                  min="100"
                  max="60000"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Expected Status</span></label>
                <input
                  type="number"
                  name="endpoint[expected_status]"
                  value={@form[:expected_status].value || "200"}
                  min="100"
                  max="599"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Expected Body Contains</span></label>
                <input
                  type="text"
                  name="endpoint[expected_body_contains]"
                  value={@form[:expected_body_contains].value}
                  class="input input-bordered input-sm w-full"
                  placeholder="Optional substring"
                />
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Headers (key: value, one per line)</span>
              </label>
              <textarea
                name="endpoint[headers]"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full"
                placeholder="Authorization: Bearer token&#10;X-Custom-Header: value"
              >{@form[:headers].value}</textarea>
            </div>

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  type="checkbox"
                  name="endpoint[enabled]"
                  value="true"
                  checked={@form[:enabled].value in [true, "true", nil]}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">Enabled</span>
              </label>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing_endpoint, do: "Update Endpoint", else: "Create Endpoint"}
              </button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">URL</th>
              <th class="text-xs uppercase">Method</th>
              <th class="text-xs uppercase">Expected</th>
              <th class="text-xs uppercase">Status</th>
              <th class="text-xs uppercase">Test</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={endpoint <- @endpoints}>
              <td>
                <div class="flex items-center gap-2">
                  <.resource_badge type="health" />
                  <span class="font-medium">{endpoint.name}</span>
                </div>
              </td>
              <td class="text-sm max-w-xs truncate" title={endpoint.url}>
                {endpoint.url}
              </td>
              <td>
                <span class="badge badge-sm badge-ghost">{endpoint.method}</span>
              </td>
              <td class="text-sm">{endpoint.expected_status}</td>
              <td>
                <span :if={endpoint.enabled} class="badge badge-sm badge-success">Enabled</span>
                <span :if={!endpoint.enabled} class="badge badge-sm badge-ghost">Disabled</span>
              </td>
              <td>
                <.test_result_badge result={Map.get(@test_results, endpoint.id)} />
              </td>
              <td class="flex gap-1">
                <button
                  phx-click="test"
                  phx-value-id={endpoint.id}
                  class="btn btn-ghost btn-xs"
                  disabled={Map.get(@test_results, endpoint.id) == :testing}
                >
                  Test
                </button>
                <button
                  phx-click="toggle_enabled"
                  phx-value-id={endpoint.id}
                  class="btn btn-ghost btn-xs"
                >
                  {if endpoint.enabled, do: "Disable", else: "Enable"}
                </button>
                <button phx-click="edit" phx-value-id={endpoint.id} class="btn btn-ghost btn-xs">
                  Edit
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={endpoint.id}
                  data-confirm="Are you sure you want to delete this health check?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@endpoints == []} class="text-center py-12 text-base-content/50">
          No health check endpoints yet. Create one to add custom health probes for rollout gates.
        </div>
      </div>
    </div>
    """
  end

  defp test_result_badge(assigns) do
    ~H"""
    <span :if={@result == nil} class="text-base-content/50">-</span>
    <span :if={@result == :testing} class="loading loading-spinner loading-xs"></span>
    <span :if={match?({:pass, _}, @result)} class="badge badge-sm badge-success">
      Pass ({elem(@result, 1)}ms)
    </span>
    <span
      :if={match?({:fail, _}, @result)}
      class="badge badge-sm badge-error"
      title={elem(@result, 1)}
    >
      Fail
    </span>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp rollouts_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts"

  defp rollouts_path(nil, project),
    do: ~p"/projects/#{project.slug}/rollouts"

  defp default_form_data do
    %{
      "method" => "GET",
      "timeout_ms" => "5000",
      "expected_status" => "200",
      "enabled" => true
    }
  end

  defp build_endpoint_attrs(params, project_id) do
    attrs = %{
      name: params["name"],
      url: params["url"],
      method: params["method"] || "GET",
      timeout_ms: parse_int(params["timeout_ms"], 5000),
      expected_status: parse_int(params["expected_status"], 200),
      expected_body_contains: empty_to_nil(params["expected_body_contains"]),
      headers: parse_headers(params["headers"] || ""),
      enabled: params["enabled"] in ["true", true]
    }

    if project_id do
      Map.put(attrs, :project_id, project_id)
    else
      attrs
    end
  end

  defp format_headers(nil), do: ""

  defp format_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp parse_headers(str) do
    str
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(str), do: str

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
