defmodule SentinelCpWeb.AuthPoliciesLive.Edit do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @auth_types ~w(jwt api_key basic forward_auth mtls)

  @impl true
  def mount(%{"project_slug" => slug, "id" => policy_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         policy when not is_nil(policy) <- Services.get_auth_policy(policy_id),
         true <- policy.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit Auth Policy #{policy.name} — #{project.name}",
         org: org,
         project: project,
         policy: policy,
         auth_types: @auth_types,
         selected_type: policy.auth_type
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_type: type)}
  end

  @impl true
  def handle_event("update_policy", params, socket) do
    policy = socket.assigns.policy
    project = socket.assigns.project

    config = build_config(params["config"] || %{})

    attrs = %{
      name: params["name"],
      description: params["description"],
      auth_type: params["auth_type"],
      config: config,
      enabled: params["enabled"] == "true"
    }

    case Services.update_auth_policy(policy, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "auth_policy", updated.id,
          project_id: project.id
        )

        show_path = show_path(socket.assigns.org, project, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Auth policy updated.")
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
      <h1 class="text-xl font-bold">Edit Auth Policy: {@policy.name}</h1>

      <.k8s_section>
        <form phx-submit="update_policy" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input type="text" name="name" value={@policy.name} required class="input input-bordered input-sm w-full" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea name="description" rows="2" class="textarea textarea-bordered textarea-sm w-full">{@policy.description}</textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Auth Type</span></label>
            <select name="auth_type" phx-change="select_type" phx-value-type="" class="select select-bordered select-sm w-48">
              <option :for={t <- @auth_types} value={t} selected={t == @selected_type}>{t}</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input type="checkbox" name="enabled" value="true" checked={@policy.enabled} class="checkbox checkbox-sm" />
              <span class="label-text font-medium">Enabled</span>
            </label>
          </div>

          <%!-- JWT config --%>
          <div :if={@selected_type == "jwt"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">JWT Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Issuer</span></label>
              <input type="text" name="config[issuer]" value={@policy.config["issuer"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Audience</span></label>
              <input type="text" name="config[audience]" value={@policy.config["audience"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">JWKS URL</span></label>
              <input type="text" name="config[jwks_url]" value={@policy.config["jwks_url"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Required Claims</span></label>
              <input type="text" name="config[required_claims]" value={@policy.config["required_claims"]} class="input input-bordered input-xs w-full" />
            </div>
          </div>

          <%!-- API Key config --%>
          <div :if={@selected_type == "api_key"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">API Key Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Header Name</span></label>
              <input type="text" name="config[header]" value={@policy.config["header"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Query Parameter</span></label>
              <input type="text" name="config[query_param]" value={@policy.config["query_param"]} class="input input-bordered input-xs w-full" />
            </div>
          </div>

          <%!-- Basic auth config --%>
          <div :if={@selected_type == "basic"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Basic Auth Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Realm</span></label>
              <input type="text" name="config[realm]" value={@policy.config["realm"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Users (htpasswd format)</span></label>
              <textarea name="config[users]" rows="4" class="textarea textarea-bordered textarea-xs w-full font-mono">{@policy.config["users"]}</textarea>
            </div>
          </div>

          <%!-- Forward auth config --%>
          <div :if={@selected_type == "forward_auth"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Forward Auth Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Auth URL</span></label>
              <input type="text" name="config[url]" value={@policy.config["url"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Headers to Forward</span></label>
              <input type="text" name="config[headers_forward]" value={@policy.config["headers_forward"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Timeout (seconds)</span></label>
              <input type="number" name="config[timeout]" value={@policy.config["timeout"]} class="input input-bordered input-xs w-24" min="1" />
            </div>
          </div>

          <%!-- mTLS config --%>
          <div :if={@selected_type == "mtls"} class="space-y-2 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">mTLS Configuration</p>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">CA Certificate (PEM)</span></label>
              <textarea name="config[ca_cert]" rows="4" class="textarea textarea-bordered textarea-xs w-full font-mono">{@policy.config["ca_cert"]}</textarea>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Required CN</span></label>
              <input type="text" name="config[required_cn]" value={@policy.config["required_cn"]} class="input input-bordered input-xs w-full" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text text-xs">Allowed OUs</span></label>
              <input type="text" name="config[allowed_ous]" value={@policy.config["allowed_ous"]} class="input input-bordered input-xs w-full" />
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
            <.link navigate={show_path(@org, @project, @policy)} class="btn btn-ghost btn-sm">Cancel</.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

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
