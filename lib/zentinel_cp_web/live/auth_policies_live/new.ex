defmodule ZentinelCpWeb.AuthPoliciesLive.New do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @auth_types ~w(jwt api_key basic forward_auth mtls)

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New Auth Policy — #{project.name}",
           org: org,
           project: project,
           auth_types: @auth_types,
           selected_type: "jwt"
         )}
    end
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_type: type)}
  end

  @impl true
  def handle_event("create_policy", params, socket) do
    project = socket.assigns.project

    config = build_config(params["config"] || %{})

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      auth_type: params["auth_type"],
      config: config,
      enabled: params["enabled"] == "true"
    }

    case Services.create_auth_policy(attrs) do
      {:ok, policy} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "auth_policy", policy.id,
          project_id: project.id
        )

        show_path = show_path(socket.assigns.org, project, policy)

        {:noreply,
         socket
         |> put_flash(:info, "Auth policy created.")
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
      <h1 class="text-xl font-bold">Create Auth Policy</h1>

      <.k8s_section>
        <form phx-submit="create_policy" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. JWT Validator"
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
            <label class="label"><span class="label-text font-medium">Auth Type</span></label>
            <select
              name="auth_type"
              phx-change="select_type"
              phx-value-type=""
              class="select select-bordered select-sm w-48"
            >
              <option :for={t <- @auth_types} value={t} selected={t == @selected_type}>{t}</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input type="checkbox" name="enabled" value="true" checked class="checkbox checkbox-sm" />
              <span class="label-text font-medium">Enabled</span>
            </label>
          </div>

          <%!-- JWT config --%>
          <div :if={@selected_type == "jwt"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">JWT Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Issuer</span></label>
              <input
                type="text"
                name="config[issuer]"
                class="input input-bordered input-xs w-full"
                placeholder="https://auth.example.com"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Audience</span></label>
              <input
                type="text"
                name="config[audience]"
                class="input input-bordered input-xs w-full"
                placeholder="my-api"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">JWKS URL</span></label>
              <input
                type="text"
                name="config[jwks_url]"
                class="input input-bordered input-xs w-full"
                placeholder="https://auth.example.com/.well-known/jwks.json"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Required Claims (comma-separated)</span>
              </label>
              <input
                type="text"
                name="config[required_claims]"
                class="input input-bordered input-xs w-full"
                placeholder="sub, email"
              />
            </div>
          </div>

          <%!-- API Key config --%>
          <div
            :if={@selected_type == "api_key"}
            class="space-y-2 ml-4 p-3 border-l-2 border-primary/30"
          >
            <p class="text-xs font-semibold text-base-content/70">API Key Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Header Name</span></label>
              <input
                type="text"
                name="config[header]"
                class="input input-bordered input-xs w-full"
                placeholder="X-API-Key"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Query Parameter</span></label>
              <input
                type="text"
                name="config[query_param]"
                class="input input-bordered input-xs w-full"
                placeholder="api_key"
              />
            </div>
          </div>

          <%!-- Basic auth config --%>
          <div :if={@selected_type == "basic"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Basic Auth Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Realm</span></label>
              <input
                type="text"
                name="config[realm]"
                class="input input-bordered input-xs w-full"
                placeholder="Restricted"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Users (htpasswd format, one per line)</span>
              </label>
              <textarea
                name="config[users]"
                rows="4"
                class="textarea textarea-bordered textarea-xs w-full font-mono"
                placeholder="user:$apr1$..."
              ></textarea>
            </div>
          </div>

          <%!-- Forward auth config --%>
          <div
            :if={@selected_type == "forward_auth"}
            class="space-y-2 ml-4 p-3 border-l-2 border-primary/30"
          >
            <p class="text-xs font-semibold text-base-content/70">Forward Auth Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Auth URL</span></label>
              <input
                type="text"
                name="config[url]"
                class="input input-bordered input-xs w-full"
                placeholder="http://auth-svc:4181/verify"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Headers to Forward (comma-separated)</span>
              </label>
              <input
                type="text"
                name="config[headers_forward]"
                class="input input-bordered input-xs w-full"
                placeholder="Authorization, X-Forwarded-User"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Timeout (seconds)</span></label>
              <input
                type="number"
                name="config[timeout]"
                class="input input-bordered input-xs w-24"
                placeholder="5"
                min="1"
              />
            </div>
          </div>

          <%!-- mTLS config --%>
          <div :if={@selected_type == "mtls"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">mTLS Configuration</p>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">CA Certificate (PEM)</span>
              </label>
              <textarea
                name="config[ca_cert]"
                rows="4"
                class="textarea textarea-bordered textarea-xs w-full font-mono"
                placeholder="-----BEGIN CERTIFICATE-----"
              ></textarea>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Required CN</span></label>
              <input
                type="text"
                name="config[required_cn]"
                class="input input-bordered input-xs w-full"
                placeholder="client.example.com"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Allowed OUs (comma-separated)</span>
              </label>
              <input
                type="text"
                name="config[allowed_ous]"
                class="input input-bordered input-xs w-full"
                placeholder="engineering, platform"
              />
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Policy</button>
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
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/auth-policies"

  defp show_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/auth-policies/#{policy.id}"

  defp show_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/auth-policies/#{policy.id}"

  defp build_config(params) when is_map(params) do
    params
    |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end)
    |> Map.new()
  end

  defp build_config(_), do: %{}
end
