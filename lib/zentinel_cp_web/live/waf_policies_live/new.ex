defmodule ZentinelCpWeb.WafPoliciesLive.New do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Waf}
  alias ZentinelCp.Waf.{WafPolicy, WafRule}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New WAF Policy — #{project.name}",
           org: org,
           project: project,
           categories: WafRule.categories(),
           modes: WafPolicy.modes(),
           sensitivities: WafPolicy.sensitivities()
         )}
    end
  end

  @impl true
  def handle_event("create", params, socket) do
    project = socket.assigns.project

    enabled_categories =
      WafRule.categories()
      |> Enum.filter(fn cat -> params["cat_#{cat}"] == "true" end)

    attrs = %{
      name: params["name"],
      description: params["description"],
      mode: params["mode"] || "block",
      sensitivity: params["sensitivity"] || "medium",
      enabled_categories: enabled_categories,
      default_action: params["default_action"] || "block",
      max_body_size: parse_int(params["max_body_size"]),
      max_header_size: parse_int(params["max_header_size"]),
      max_uri_length: parse_int(params["max_uri_length"]),
      project_id: project.id
    }

    case Waf.create_policy(attrs) do
      {:ok, policy} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "waf_policy", policy.id,
          project_id: project.id
        )

        {:noreply,
         push_navigate(socket, to: show_path(socket.assigns.org, project, policy))
         |> put_flash(:info, "WAF policy created.")}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Error: #{msg}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-xl font-bold">New WAF Policy</h1>

      <.k8s_section>
        <form phx-submit="create" class="space-y-4 max-w-xl">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API Protection Policy"
              required
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              class="textarea textarea-bordered textarea-sm w-full"
              rows="2"
              placeholder="Optional description..."
            />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Mode</span></label>
              <select name="mode" class="select select-bordered select-sm">
                <option :for={mode <- @modes} value={mode}>{mode}</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Sensitivity</span></label>
              <select name="sensitivity" class="select select-bordered select-sm">
                <option :for={s <- @sensitivities} value={s} selected={s == "medium"}>{s}</option>
              </select>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Default Action</span></label>
            <select name="default_action" class="select select-bordered select-sm w-40">
              <option value="block" selected>block</option>
              <option value="log">log</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Enabled Categories</span>
            </label>
            <div class="flex flex-wrap gap-3">
              <label :for={cat <- @categories} class="flex items-center gap-1 cursor-pointer">
                <input type="hidden" name={"cat_#{cat}"} value="false" />
                <input type="checkbox" name={"cat_#{cat}"} value="true" class="checkbox checkbox-sm" />
                <span class="text-sm">{cat}</span>
              </label>
            </div>
          </div>

          <div class="divider text-xs text-base-content/50">Optional Limits</div>

          <div class="grid grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Max Body Size (bytes)</span>
              </label>
              <input
                type="number"
                name="max_body_size"
                class="input input-bordered input-sm"
                placeholder="1048576"
                min="1"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Max Header Size (bytes)</span>
              </label>
              <input
                type="number"
                name="max_header_size"
                class="input input-bordered input-sm"
                placeholder="8192"
                min="1"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs">Max URI Length (bytes)</span>
              </label>
              <input
                type="number"
                name="max_uri_length"
                class="input input-bordered input-sm"
                placeholder="2048"
                min="1"
              />
            </div>
          </div>

          <div class="flex gap-2 pt-2">
            <button type="submit" class="btn btn-primary btn-sm">Create Policy</button>
            <.link navigate={index_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp show_path(%{slug: org_slug}, project, policy),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies/#{policy.id}"

  defp show_path(nil, project, policy),
    do: ~p"/projects/#{project.slug}/waf/policies/#{policy.id}"

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/waf/policies"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/waf/policies"
end
