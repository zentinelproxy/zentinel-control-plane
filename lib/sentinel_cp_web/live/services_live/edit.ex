defmodule SentinelCpWeb.ServicesLive.Edit do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => service_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         service when not is_nil(service) <- Services.get_service(service_id),
         true <- service.project_id == project.id do
      route_type =
        cond do
          service.upstream_url -> "upstream"
          service.redirect_url -> "redirect"
          true -> "static"
        end

      auth_policies = Services.list_auth_policies(project.id)

      {:ok,
       assign(socket,
         page_title: "Edit Service #{service.name} — #{project.name}",
         org: org,
         project: project,
         service: service,
         route_type: route_type,
         auth_policies: auth_policies,
         show_retry: service.retry != %{} && service.retry != nil,
         show_cache: service.cache != %{} && service.cache != nil,
         show_rate_limit: service.rate_limit != %{} && service.rate_limit != nil,
         show_health_check: service.health_check != %{} && service.health_check != nil,
         show_cors: service.cors != %{} && service.cors != nil,
         show_access_control: service.access_control != %{} && service.access_control != nil,
         show_compression: service.compression != %{} && service.compression != nil,
         show_path_rewrite: service.path_rewrite != %{} && service.path_rewrite != nil,
         show_security: service.security != %{} && service.security != nil,
         show_request_transform: service.request_transform != %{} && service.request_transform != nil,
         show_response_transform: service.response_transform != %{} && service.response_transform != nil
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("switch_route_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, route_type: type)}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    key = String.to_existing_atom("show_#{section}")
    {:noreply, assign(socket, [{key, !socket.assigns[key]}])}
  end

  @impl true
  def handle_event("update_service", params, socket) do
    service = socket.assigns.service
    project = socket.assigns.project

    attrs = %{
      name: params["name"],
      description: params["description"],
      route_path: params["route_path"],
      timeout_seconds: parse_int(params["timeout_seconds"])
    }

    attrs =
      case socket.assigns.route_type do
        "upstream" ->
          attrs
          |> Map.put(:upstream_url, params["upstream_url"])
          |> Map.put(:respond_status, nil)
          |> Map.put(:respond_body, nil)
          |> Map.put(:redirect_url, nil)

        "static" ->
          attrs
          |> Map.put(:upstream_url, nil)
          |> Map.put(:respond_status, parse_int(params["respond_status"]))
          |> Map.put(:respond_body, params["respond_body"])
          |> Map.put(:redirect_url, nil)

        "redirect" ->
          attrs
          |> Map.put(:upstream_url, nil)
          |> Map.put(:respond_status, parse_int(params["redirect_status"]))
          |> Map.put(:respond_body, nil)
          |> Map.put(:redirect_url, params["redirect_url"])
      end

    # auth_policy_id: empty string means clear, non-empty means set
    attrs =
      case params["auth_policy_id"] do
        "" -> Map.put(attrs, :auth_policy_id, nil)
        nil -> attrs
        id -> Map.put(attrs, :auth_policy_id, id)
      end

    attrs = maybe_put_map(attrs, :retry, params, "retry")
    attrs = maybe_put_map(attrs, :cache, params, "cache")
    attrs = maybe_put_map(attrs, :rate_limit, params, "rate_limit")
    attrs = maybe_put_map(attrs, :health_check, params, "health_check")
    attrs = maybe_put_map(attrs, :cors, params, "cors")
    attrs = maybe_put_map(attrs, :access_control, params, "access_control")
    attrs = maybe_put_map(attrs, :compression, params, "compression")
    attrs = maybe_put_map(attrs, :path_rewrite, params, "path_rewrite")
    attrs = maybe_put_map(attrs, :security, params, "security")
    attrs = maybe_put_map(attrs, :request_transform, params, "request_transform")
    attrs = maybe_put_map(attrs, :response_transform, params, "response_transform")

    case Services.update_service(service, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "service", updated.id,
          project_id: project.id
        )

        show_path = service_show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Service updated.")
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
      <h1 class="text-xl font-bold">Edit Service: {@service.name}</h1>

      <.k8s_section>
        <form phx-submit="update_service" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@service.name}
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
            >{@service.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Route Path</span></label>
            <input
              type="text"
              name="route_path"
              value={@service.route_path}
              required
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Route Type</span></label>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="switch_route_type"
                phx-value-type="upstream"
                class={["btn btn-sm", (@route_type == "upstream" && "btn-primary") || "btn-ghost"]}
              >
                Upstream Proxy
              </button>
              <button
                type="button"
                phx-click="switch_route_type"
                phx-value-type="static"
                class={["btn btn-sm", (@route_type == "static" && "btn-primary") || "btn-ghost"]}
              >
                Static Response
              </button>
              <button
                type="button"
                phx-click="switch_route_type"
                phx-value-type="redirect"
                class={["btn btn-sm", (@route_type == "redirect" && "btn-primary") || "btn-ghost"]}
              >
                Redirect
              </button>
            </div>
          </div>

          <div :if={@route_type == "upstream"} class="form-control">
            <label class="label"><span class="label-text font-medium">Upstream URL</span></label>
            <input
              type="text"
              name="upstream_url"
              value={@service.upstream_url}
              required
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div :if={@route_type == "static"} class="space-y-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Response Status</span></label>
              <input
                type="number"
                name="respond_status"
                value={@service.respond_status}
                required
                class="input input-bordered input-sm w-32"
                min="100"
                max="599"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Response Body</span></label>
              <textarea
                name="respond_body"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full font-mono"
              >{@service.respond_body}</textarea>
            </div>
          </div>

          <div :if={@route_type == "redirect"} class="space-y-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Redirect URL</span></label>
              <input
                type="text"
                name="redirect_url"
                value={@service.redirect_url}
                required
                class="input input-bordered input-sm w-full"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Status Code</span></label>
              <select name="redirect_status" class="select select-bordered select-sm w-40">
                <option value="301" selected={@service.respond_status == 301}>301 Permanent</option>
                <option value="302" selected={@service.respond_status == 302}>302 Temporary</option>
              </select>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Timeout (seconds)</span></label>
            <input
              type="number"
              name="timeout_seconds"
              value={@service.timeout_seconds}
              class="input input-bordered input-sm w-32"
              min="1"
            />
          </div>

          <div :if={@auth_policies != []} class="form-control">
            <label class="label"><span class="label-text font-medium">Auth Policy</span></label>
            <select name="auth_policy_id" class="select select-bordered select-sm w-64">
              <option value="">None</option>
              <option :for={p <- @auth_policies} value={p.id} selected={p.id == @service.auth_policy_id}>{p.name} ({p.auth_type})</option>
            </select>
          </div>

          <%!-- Advanced Sections --%>
          <div class="divider text-xs text-base-content/50">Advanced Settings</div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="retry"
              class="btn btn-ghost btn-xs"
            >
              {if @show_retry, do: "▼", else: "▶"} Retry Policy
            </button>
            <div :if={@show_retry} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Attempts</span></label>
                <input
                  type="number"
                  name="retry[attempts]"
                  value={@service.retry["attempts"]}
                  class="input input-bordered input-xs w-24"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Backoff</span></label>
                <input
                  type="text"
                  name="retry[backoff]"
                  value={@service.retry["backoff"]}
                  class="input input-bordered input-xs w-40"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="cache"
              class="btn btn-ghost btn-xs"
            >
              {if @show_cache, do: "▼", else: "▶"} Cache
            </button>
            <div :if={@show_cache} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">TTL (seconds)</span></label>
                <input
                  type="number"
                  name="cache[ttl]"
                  value={@service.cache["ttl"]}
                  class="input input-bordered input-xs w-24"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Vary</span></label>
                <input
                  type="text"
                  name="cache[vary]"
                  value={@service.cache["vary"]}
                  class="input input-bordered input-xs w-48"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="rate_limit"
              class="btn btn-ghost btn-xs"
            >
              {if @show_rate_limit, do: "▼", else: "▶"} Rate Limit
            </button>
            <div :if={@show_rate_limit} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Requests</span></label>
                <input
                  type="number"
                  name="rate_limit[requests]"
                  value={@service.rate_limit["requests"]}
                  class="input input-bordered input-xs w-24"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Window</span></label>
                <input
                  type="text"
                  name="rate_limit[window]"
                  value={@service.rate_limit["window"]}
                  class="input input-bordered input-xs w-24"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">By</span></label>
                <input
                  type="text"
                  name="rate_limit[by]"
                  value={@service.rate_limit["by"]}
                  class="input input-bordered input-xs w-32"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="health_check"
              class="btn btn-ghost btn-xs"
            >
              {if @show_health_check, do: "▼", else: "▶"} Health Check
            </button>
            <div :if={@show_health_check} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Path</span></label>
                <input
                  type="text"
                  name="health_check[path]"
                  value={@service.health_check["path"]}
                  class="input input-bordered input-xs w-48"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-xs">Interval (seconds)</span>
                </label>
                <input
                  type="number"
                  name="health_check[interval]"
                  value={@service.health_check["interval"]}
                  class="input input-bordered input-xs w-24"
                  min="1"
                />
              </div>
            </div>
          </div>

          <div class="divider text-xs text-base-content/50">Policy Settings</div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="cors"
              class="btn btn-ghost btn-xs"
            >
              {if @show_cors, do: "▼", else: "▶"} CORS
            </button>
            <div :if={@show_cors} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Origins</span></label>
                <input
                  type="text"
                  name="cors[allowed_origins]"
                  value={@service.cors["allowed_origins"]}
                  class="input input-bordered input-xs w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Methods</span></label>
                <input
                  type="text"
                  name="cors[allowed_methods]"
                  value={@service.cors["allowed_methods"]}
                  class="input input-bordered input-xs w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Headers</span></label>
                <input
                  type="text"
                  name="cors[allowed_headers]"
                  value={@service.cors["allowed_headers"]}
                  class="input input-bordered input-xs w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Age (seconds)</span></label>
                <input
                  type="number"
                  name="cors[max_age]"
                  value={@service.cors["max_age"]}
                  class="input input-bordered input-xs w-24"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input
                    type="checkbox"
                    name="cors[allow_credentials]"
                    value="true"
                    checked={@service.cors["allow_credentials"] == "true"}
                    class="checkbox checkbox-xs"
                  />
                  <span class="label-text text-xs">Allow Credentials</span>
                </label>
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="access_control"
              class="btn btn-ghost btn-xs"
            >
              {if @show_access_control, do: "▼", else: "▶"} IP Access Control
            </button>
            <div :if={@show_access_control} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allow CIDRs (one per line)</span></label>
                <textarea
                  name="access_control[allow]"
                  rows="3"
                  class="textarea textarea-bordered textarea-xs w-full font-mono"
                >{@service.access_control["allow"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Deny CIDRs (one per line)</span></label>
                <textarea
                  name="access_control[deny]"
                  rows="3"
                  class="textarea textarea-bordered textarea-xs w-full font-mono"
                >{@service.access_control["deny"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Mode</span></label>
                <select name="access_control[mode]" class="select select-bordered select-xs w-40">
                  <option value="">—</option>
                  <option value="deny_first" selected={@service.access_control["mode"] == "deny_first"}>Deny First</option>
                  <option value="allow_first" selected={@service.access_control["mode"] == "allow_first"}>Allow First</option>
                </select>
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="compression"
              class="btn btn-ghost btn-xs"
            >
              {if @show_compression, do: "▼", else: "▶"} Compression
            </button>
            <div :if={@show_compression} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Algorithms</span></label>
                <input
                  type="text"
                  name="compression[algorithms]"
                  value={@service.compression["algorithms"]}
                  class="input input-bordered input-xs w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Min Size (bytes)</span></label>
                <input
                  type="number"
                  name="compression[min_size]"
                  value={@service.compression["min_size"]}
                  class="input input-bordered input-xs w-32"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Content Types</span></label>
                <input
                  type="text"
                  name="compression[content_types]"
                  value={@service.compression["content_types"]}
                  class="input input-bordered input-xs w-full"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="path_rewrite"
              class="btn btn-ghost btn-xs"
            >
              {if @show_path_rewrite, do: "▼", else: "▶"} Path Rewrite
            </button>
            <div :if={@show_path_rewrite} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Strip Prefix</span></label>
                <input
                  type="text"
                  name="path_rewrite[strip_prefix]"
                  value={@service.path_rewrite["strip_prefix"]}
                  class="input input-bordered input-xs w-48"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Prefix</span></label>
                <input
                  type="text"
                  name="path_rewrite[add_prefix]"
                  value={@service.path_rewrite["add_prefix"]}
                  class="input input-bordered input-xs w-48"
                />
              </div>
            </div>
          </div>

          <div class="divider text-xs text-base-content/50">Security & Transforms</div>

          <div>
            <button type="button" phx-click="toggle_section" phx-value-section="security" class="btn btn-ghost btn-xs">
              {if @show_security, do: "▼", else: "▶"} Security / WAF
            </button>
            <div :if={@show_security} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Body Size (bytes)</span></label>
                <input type="number" name="security[max_body_size]" value={@service.security["max_body_size"]} class="input input-bordered input-xs w-32" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Header Size (bytes)</span></label>
                <input type="number" name="security[max_header_size]" value={@service.security["max_header_size"]} class="input input-bordered input-xs w-32" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max URI Length</span></label>
                <input type="number" name="security[max_uri_length]" value={@service.security["max_uri_length"]} class="input input-bordered input-xs w-32" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Content Types</span></label>
                <input type="text" name="security[allowed_content_types]" value={@service.security["allowed_content_types"]} class="input input-bordered input-xs w-full" />
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_sqli]" value="true" checked={@service.security["block_sqli"] == "true"} class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block SQL Injection</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_xss]" value="true" checked={@service.security["block_xss"] == "true"} class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block XSS</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_path_traversal]" value="true" checked={@service.security["block_path_traversal"] == "true"} class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block Path Traversal</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Custom Rules</span></label>
                <textarea name="security[custom_rules]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.security["custom_rules"]}</textarea>
              </div>
            </div>
          </div>

          <div>
            <button type="button" phx-click="toggle_section" phx-value-section="request_transform" class="btn btn-ghost btn-xs">
              {if @show_request_transform, do: "▼", else: "▶"} Request Transform
            </button>
            <div :if={@show_request_transform} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Headers</span></label>
                <textarea name="request_transform[add_headers]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.request_transform["add_headers"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Headers</span></label>
                <input type="text" name="request_transform[remove_headers]" value={@service.request_transform["remove_headers"]} class="input input-bordered input-xs w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Rename Headers</span></label>
                <textarea name="request_transform[rename_headers]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.request_transform["rename_headers"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Query Params</span></label>
                <textarea name="request_transform[add_query_params]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.request_transform["add_query_params"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Query Params</span></label>
                <input type="text" name="request_transform[remove_query_params]" value={@service.request_transform["remove_query_params"]} class="input input-bordered input-xs w-full" />
              </div>
            </div>
          </div>

          <div>
            <button type="button" phx-click="toggle_section" phx-value-section="response_transform" class="btn btn-ghost btn-xs">
              {if @show_response_transform, do: "▼", else: "▶"} Response Transform
            </button>
            <div :if={@show_response_transform} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Headers</span></label>
                <textarea name="response_transform[add_headers]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.response_transform["add_headers"]}</textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Headers</span></label>
                <input type="text" name="response_transform[remove_headers]" value={@service.response_transform["remove_headers"]} class="input input-bordered input-xs w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Rename Headers</span></label>
                <textarea name="response_transform[rename_headers]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono">{@service.response_transform["rename_headers"]}</textarea>
              </div>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={service_show_path(@org, @project, @service)} class="btn btn-ghost btn-sm">
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

  defp service_show_path(%{slug: org_slug}, project, service),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/#{service.id}"

  defp service_show_path(nil, project, service),
    do: ~p"/projects/#{project.slug}/services/#{service.id}"

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp maybe_put_map(attrs, key, params, param_key) do
    case params[param_key] do
      nil ->
        attrs

      %{} = map ->
        cleaned = map |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end) |> Map.new()

        if cleaned == %{} do
          Map.put(attrs, key, %{})
        else
          cleaned =
            Map.new(cleaned, fn {k, v} ->
              case Integer.parse(v) do
                {n, ""} -> {k, n}
                _ -> {k, v}
              end
            end)

          Map.put(attrs, key, cleaned)
        end

      _ ->
        attrs
    end
  end
end
