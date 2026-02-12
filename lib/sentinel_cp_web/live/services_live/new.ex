defmodule SentinelCpWeb.ServicesLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        auth_policies = Services.list_auth_policies(project.id)
        upstream_groups = Services.list_upstream_groups(project.id)
        templates = Services.list_templates(project.id)

        # Check if a template_id was passed in query params
        template_data =
          case params["template_id"] do
            nil -> nil
            id -> Services.get_template(id) |> template_data_or_nil()
          end

        {:ok,
         assign(socket,
           page_title: "New Service — #{project.name}",
           org: org,
           project: project,
           route_type: "upstream",
           auth_policies: auth_policies,
           upstream_groups: upstream_groups,
           templates: templates,
           applied_template: template_data,
           show_retry: false,
           show_cache: false,
           show_rate_limit: false,
           show_health_check: false,
           show_cors: false,
           show_access_control: false,
           show_compression: false,
           show_path_rewrite: false,
           show_security: false,
           show_request_transform: false,
           show_response_transform: false,
           show_traffic_split: false,
           split_count: 0,
           match_rule_count: 0
         )}
    end
  end

  @impl true
  def handle_event("apply_template", %{"template_id" => ""}, socket) do
    {:noreply, assign(socket, applied_template: nil)}
  end

  @impl true
  def handle_event("apply_template", %{"template_id" => template_id}, socket) do
    case Services.get_template(template_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      template ->
        data = template.template_data || %{}

        route_type =
          cond do
            data["upstream_url"] -> "upstream"
            data["redirect_url"] -> "redirect"
            data["respond_status"] -> "static"
            true -> "upstream"
          end

        {:noreply, assign(socket, applied_template: data, route_type: route_type)}
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
  def handle_event("add_split", _, socket) do
    {:noreply, assign(socket, split_count: socket.assigns.split_count + 1)}
  end

  @impl true
  def handle_event("remove_split", _, socket) do
    {:noreply, assign(socket, split_count: max(0, socket.assigns.split_count - 1))}
  end

  @impl true
  def handle_event("add_match_rule", _, socket) do
    {:noreply, assign(socket, match_rule_count: socket.assigns.match_rule_count + 1)}
  end

  @impl true
  def handle_event("remove_match_rule", _, socket) do
    {:noreply, assign(socket, match_rule_count: max(0, socket.assigns.match_rule_count - 1))}
  end

  @impl true
  def handle_event("create_service", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      route_path: params["route_path"],
      timeout_seconds: parse_int(params["timeout_seconds"])
    }

    attrs =
      case socket.assigns.route_type do
        "upstream" ->
          Map.put(attrs, :upstream_url, params["upstream_url"])

        "static" ->
          attrs
          |> Map.put(:respond_status, parse_int(params["respond_status"]))
          |> Map.put(:respond_body, params["respond_body"])

        "redirect" ->
          attrs
          |> Map.put(:redirect_url, params["redirect_url"])
          |> Map.put(:respond_status, parse_int(params["redirect_status"]))
      end

    attrs = maybe_put_fk(attrs, :auth_policy_id, params["auth_policy_id"])

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
    attrs = maybe_put_traffic_split(attrs, params)

    case Services.create_service(attrs) do
      {:ok, service} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "service", service.id,
          project_id: project.id
        )

        show_path = service_show_path(socket.assigns.org, project, service)

        {:noreply,
         socket
         |> put_flash(:info, "Service created.")
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
      <h1 class="text-xl font-bold">Create Service</h1>

      <.k8s_section :if={@templates != []}>
        <form phx-change="apply_template" class="form-control">
          <label class="label"><span class="label-text font-medium">Start from Template</span></label>
          <select name="template_id" class="select select-bordered select-sm w-64">
            <option value="">None (blank)</option>
            <option :for={t <- @templates} value={t.id}>
              {t.name} ({t.category})
            </option>
          </select>
          <label class="label">
            <span class="label-text-alt text-base-content/50">Pre-fills the form with template defaults</span>
          </label>
        </form>
      </.k8s_section>

      <.k8s_section>
        <form phx-submit="create_service" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API Backend"
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
            <label class="label"><span class="label-text font-medium">Route Path</span></label>
            <input
              type="text"
              name="route_path"
              value={@applied_template && @applied_template["route_path"]}
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. /api/v1/*"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Must start with /</span>
            </label>
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
              value={@applied_template && @applied_template["upstream_url"]}
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. http://api-backend:8080"
            />
          </div>

          <div :if={@route_type == "static"} class="space-y-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Response Status</span></label>
              <input
                type="number"
                name="respond_status"
                required
                class="input input-bordered input-sm w-32"
                placeholder="200"
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
                placeholder="OK"
              ></textarea>
            </div>
          </div>

          <div :if={@route_type == "redirect"} class="space-y-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Redirect URL</span></label>
              <input
                type="text"
                name="redirect_url"
                required
                class="input input-bordered input-sm w-full"
                placeholder="e.g. https://new-domain.com/api"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Status Code</span></label>
              <select name="redirect_status" class="select select-bordered select-sm w-40">
                <option value="301">301 Permanent</option>
                <option value="302">302 Temporary</option>
              </select>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Timeout (seconds)</span></label>
            <input
              type="number"
              name="timeout_seconds"
              class="input input-bordered input-sm w-32"
              placeholder="30"
              min="1"
            />
          </div>

          <div :if={@auth_policies != []} class="form-control">
            <label class="label"><span class="label-text font-medium">Auth Policy</span></label>
            <select name="auth_policy_id" class="select select-bordered select-sm w-64">
              <option value="">None</option>
              <option :for={p <- @auth_policies} value={p.id}>{p.name} ({p.auth_type})</option>
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
                  class="input input-bordered input-xs w-24"
                  placeholder="3"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Backoff</span></label>
                <input
                  type="text"
                  name="retry[backoff]"
                  class="input input-bordered input-xs w-40"
                  placeholder="exponential"
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
                  class="input input-bordered input-xs w-24"
                  placeholder="3600"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Vary</span></label>
                <input
                  type="text"
                  name="cache[vary]"
                  class="input input-bordered input-xs w-48"
                  placeholder="Accept-Encoding"
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
                  class="input input-bordered input-xs w-24"
                  placeholder="100"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Window</span></label>
                <input
                  type="text"
                  name="rate_limit[window]"
                  class="input input-bordered input-xs w-24"
                  placeholder="60s"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">By</span></label>
                <input
                  type="text"
                  name="rate_limit[by]"
                  class="input input-bordered input-xs w-32"
                  placeholder="client_ip"
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
                  class="input input-bordered input-xs w-48"
                  placeholder="/health"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-xs">Interval (seconds)</span>
                </label>
                <input
                  type="number"
                  name="health_check[interval]"
                  class="input input-bordered input-xs w-24"
                  placeholder="10"
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
                  class="input input-bordered input-xs w-full"
                  placeholder="*, https://example.com"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Methods</span></label>
                <input
                  type="text"
                  name="cors[allowed_methods]"
                  class="input input-bordered input-xs w-full"
                  placeholder="GET, POST, PUT, DELETE"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Headers</span></label>
                <input
                  type="text"
                  name="cors[allowed_headers]"
                  class="input input-bordered input-xs w-full"
                  placeholder="Content-Type, Authorization"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Age (seconds)</span></label>
                <input
                  type="number"
                  name="cors[max_age]"
                  class="input input-bordered input-xs w-24"
                  placeholder="86400"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="cors[allow_credentials]" value="true" class="checkbox checkbox-xs" />
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
                  placeholder="10.0.0.0/8&#10;192.168.0.0/16"
                ></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Deny CIDRs (one per line)</span></label>
                <textarea
                  name="access_control[deny]"
                  rows="3"
                  class="textarea textarea-bordered textarea-xs w-full font-mono"
                  placeholder="0.0.0.0/0"
                ></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Mode</span></label>
                <select name="access_control[mode]" class="select select-bordered select-xs w-40">
                  <option value="">—</option>
                  <option value="deny_first">Deny First</option>
                  <option value="allow_first">Allow First</option>
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
                  class="input input-bordered input-xs w-full"
                  placeholder="gzip, brotli, zstd"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Min Size (bytes)</span></label>
                <input
                  type="number"
                  name="compression[min_size]"
                  class="input input-bordered input-xs w-32"
                  placeholder="1024"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Content Types</span></label>
                <input
                  type="text"
                  name="compression[content_types]"
                  class="input input-bordered input-xs w-full"
                  placeholder="text/html, application/json"
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
                  class="input input-bordered input-xs w-48"
                  placeholder="/api/v1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Prefix</span></label>
                <input
                  type="text"
                  name="path_rewrite[add_prefix]"
                  class="input input-bordered input-xs w-48"
                  placeholder="/v2"
                />
              </div>
            </div>
          </div>

          <div :if={@upstream_groups != []} class="divider text-xs text-base-content/50">Traffic Splitting</div>

          <div :if={@upstream_groups != []}>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="traffic_split"
              class="btn btn-ghost btn-xs"
            >
              {if @show_traffic_split, do: "▼", else: "▶"} Traffic Split
            </button>
            <div :if={@show_traffic_split} class="ml-4 mt-2 space-y-3">
              <div class="text-xs text-base-content/50 mb-2">
                Split traffic between upstream groups by weight or match rules.
              </div>
              <div>
                <h4 class="text-xs font-medium mb-1">Weighted Splits</h4>
                <div :for={i <- 0..(@split_count - 1)} class="flex gap-2 items-end mb-2">
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Upstream Group</span></label>
                    <select name={"split_group_#{i}"} class="select select-bordered select-xs w-48">
                      <option value="">Select group</option>
                      <option :for={g <- @upstream_groups} value={g.id}>{g.name}</option>
                    </select>
                  </div>
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Weight</span></label>
                    <input type="number" name={"split_weight_#{i}"} class="input input-bordered input-xs w-20" placeholder="50" min="0" max="100" />
                  </div>
                </div>
                <div class="flex gap-1">
                  <button type="button" phx-click="add_split" class="btn btn-ghost btn-xs">+ Add Split</button>
                  <button :if={@split_count > 0} type="button" phx-click="remove_split" class="btn btn-ghost btn-xs text-error">Remove</button>
                </div>
              </div>
              <div>
                <h4 class="text-xs font-medium mb-1">Match Rules</h4>
                <div :for={i <- 0..(@match_rule_count - 1)} class="flex gap-2 items-end mb-2">
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Type</span></label>
                    <select name={"match_type_#{i}"} class="select select-bordered select-xs w-28">
                      <option value="header">Header</option>
                      <option value="cookie">Cookie</option>
                    </select>
                  </div>
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Key</span></label>
                    <input type="text" name={"match_key_#{i}"} class="input input-bordered input-xs w-32" placeholder="X-Version" />
                  </div>
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Value</span></label>
                    <input type="text" name={"match_value_#{i}"} class="input input-bordered input-xs w-24" placeholder="v2" />
                  </div>
                  <div class="form-control">
                    <label :if={i == 0} class="label"><span class="label-text text-xs">Target Group</span></label>
                    <select name={"match_target_#{i}"} class="select select-bordered select-xs w-48">
                      <option value="">Select group</option>
                      <option :for={g <- @upstream_groups} value={g.id}>{g.name}</option>
                    </select>
                  </div>
                </div>
                <div class="flex gap-1">
                  <button type="button" phx-click="add_match_rule" class="btn btn-ghost btn-xs">+ Add Rule</button>
                  <button :if={@match_rule_count > 0} type="button" phx-click="remove_match_rule" class="btn btn-ghost btn-xs text-error">Remove</button>
                </div>
              </div>
            </div>
          </div>

          <div class="divider text-xs text-base-content/50">Security & Transforms</div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="security"
              class="btn btn-ghost btn-xs"
            >
              {if @show_security, do: "▼", else: "▶"} Security / WAF
            </button>
            <div :if={@show_security} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Body Size (bytes)</span></label>
                <input type="number" name="security[max_body_size]" class="input input-bordered input-xs w-32" placeholder="1048576" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max Header Size (bytes)</span></label>
                <input type="number" name="security[max_header_size]" class="input input-bordered input-xs w-32" placeholder="8192" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Max URI Length</span></label>
                <input type="number" name="security[max_uri_length]" class="input input-bordered input-xs w-32" placeholder="2048" min="0" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Allowed Content Types (comma-separated)</span></label>
                <input type="text" name="security[allowed_content_types]" class="input input-bordered input-xs w-full" placeholder="application/json, text/plain" />
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_sqli]" value="true" class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block SQL Injection</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_xss]" value="true" class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block XSS</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2 justify-start">
                  <input type="checkbox" name="security[block_path_traversal]" value="true" class="checkbox checkbox-xs" />
                  <span class="label-text text-xs">Block Path Traversal</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Custom Rules</span></label>
                <textarea name="security[custom_rules]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="Custom WAF rules"></textarea>
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="request_transform"
              class="btn btn-ghost btn-xs"
            >
              {if @show_request_transform, do: "▼", else: "▶"} Request Transform
            </button>
            <div :if={@show_request_transform} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Headers (key: value, one per line)</span></label>
                <textarea name="request_transform[add_headers]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="X-Custom: value"></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Headers (comma-separated)</span></label>
                <input type="text" name="request_transform[remove_headers]" class="input input-bordered input-xs w-full" placeholder="X-Forwarded-For, X-Real-IP" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Rename Headers (old: new, one per line)</span></label>
                <textarea name="request_transform[rename_headers]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="X-Old: X-New"></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Query Params (key=value, one per line)</span></label>
                <textarea name="request_transform[add_query_params]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="version=2"></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Query Params (comma-separated)</span></label>
                <input type="text" name="request_transform[remove_query_params]" class="input input-bordered input-xs w-full" placeholder="debug, trace" />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="response_transform"
              class="btn btn-ghost btn-xs"
            >
              {if @show_response_transform, do: "▼", else: "▶"} Response Transform
            </button>
            <div :if={@show_response_transform} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Add Headers (key: value, one per line)</span></label>
                <textarea name="response_transform[add_headers]" rows="3" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="X-Frame-Options: DENY"></textarea>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Remove Headers (comma-separated)</span></label>
                <input type="text" name="response_transform[remove_headers]" class="input input-bordered input-xs w-full" placeholder="Server, X-Powered-By" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Rename Headers (old: new, one per line)</span></label>
                <textarea name="response_transform[rename_headers]" rows="2" class="textarea textarea-bordered textarea-xs w-full font-mono" placeholder="X-Old: X-New"></textarea>
              </div>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Service</button>
            <.link navigate={project_services_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp template_data_or_nil(nil), do: nil
  defp template_data_or_nil(template), do: template.template_data

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_services_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp project_services_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

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

  defp maybe_put_fk(attrs, _key, nil), do: attrs
  defp maybe_put_fk(attrs, _key, ""), do: attrs
  defp maybe_put_fk(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_traffic_split(attrs, params) do
    splits =
      0..20
      |> Enum.map(fn i ->
        group_id = params["split_group_#{i}"]
        weight = params["split_weight_#{i}"]

        if group_id && group_id != "" && weight && weight != "" do
          %{"upstream_group_id" => group_id, "weight" => parse_int(weight) || 0}
        end
      end)
      |> Enum.reject(&is_nil/1)

    match_rules =
      0..20
      |> Enum.map(fn i ->
        type = params["match_type_#{i}"]
        key = params["match_key_#{i}"]
        value = params["match_value_#{i}"]
        target = params["match_target_#{i}"]

        if type && key && key != "" && target && target != "" do
          base = %{"type" => type, "value" => value || "", "target_group_id" => target}

          case type do
            "header" -> Map.put(base, "header", key)
            "cookie" -> Map.put(base, "cookie", key)
            _ -> base
          end
        end
      end)
      |> Enum.reject(&is_nil/1)

    if splits == [] and match_rules == [] do
      attrs
    else
      Map.put(attrs, :traffic_split, %{"splits" => splits, "match_rules" => match_rules})
    end
  end

  defp maybe_put_map(attrs, key, params, param_key) do
    case params[param_key] do
      nil ->
        attrs

      %{} = map ->
        cleaned = map |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end) |> Map.new()

        if cleaned == %{} do
          attrs
        else
          # Convert numeric string values to integers where possible
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
