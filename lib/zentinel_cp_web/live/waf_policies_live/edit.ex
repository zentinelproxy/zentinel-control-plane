defmodule ZentinelCpWeb.WafPoliciesLive.Edit do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Waf}
  alias ZentinelCp.Waf.{WafPolicy, WafRule}

  @impl true
  def mount(%{"project_slug" => slug, "id" => policy_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         policy when not is_nil(policy) <- Waf.get_policy!(policy_id),
         true <- policy.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Edit WAF Policy: #{policy.name} — #{project.name}",
         org: org,
         project: project,
         policy: policy,
         categories: WafRule.categories(),
         modes: WafPolicy.modes(),
         sensitivities: WafPolicy.sensitivities()
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("update", params, socket) do
    policy = socket.assigns.policy
    project = socket.assigns.project

    enabled_categories =
      WafRule.categories()
      |> Enum.filter(fn cat -> params["cat_#{cat}"] == "true" end)

    attrs = %{
      name: params["name"],
      description: params["description"],
      mode: params["mode"],
      sensitivity: params["sensitivity"],
      enabled_categories: enabled_categories,
      default_action: params["default_action"],
      max_body_size: parse_int(params["max_body_size"]),
      max_header_size: parse_int(params["max_header_size"]),
      max_uri_length: parse_int(params["max_uri_length"])
    }

    case Waf.update_policy(policy, attrs) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "waf_policy", updated.id,
          project_id: project.id
        )

        {:noreply,
         push_navigate(socket, to: show_path(socket.assigns.org, project, updated))
         |> put_flash(:info, "WAF policy updated.")}

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
      <h1 class="text-xl font-bold">Edit WAF Policy: {@policy.name}</h1>

      <.k8s_section>
        <form phx-submit="update" class="space-y-4 max-w-xl">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              value={@policy.name}
              class="input input-bordered input-sm w-full"
              required
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              class="textarea textarea-bordered textarea-sm w-full"
              rows="2"
            >{@policy.description}</textarea>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Mode</span></label>
              <select name="mode" class="select select-bordered select-sm">
                <option :for={mode <- @modes} value={mode} selected={mode == @policy.mode}>
                  {mode}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Sensitivity</span></label>
              <select name="sensitivity" class="select select-bordered select-sm">
                <option
                  :for={s <- @sensitivities}
                  value={s}
                  selected={s == @policy.sensitivity}
                >
                  {s}
                </option>
              </select>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Default Action</span></label>
            <select name="default_action" class="select select-bordered select-sm w-40">
              <option value="block" selected={@policy.default_action == "block"}>block</option>
              <option value="log" selected={@policy.default_action == "log"}>log</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Enabled Categories</span>
            </label>
            <div class="flex flex-wrap gap-3">
              <label :for={cat <- @categories} class="flex items-center gap-1 cursor-pointer">
                <input type="hidden" name={"cat_#{cat}"} value="false" />
                <input
                  type="checkbox"
                  name={"cat_#{cat}"}
                  value="true"
                  class="checkbox checkbox-sm"
                  checked={cat in (@policy.enabled_categories || [])}
                />
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
                value={@policy.max_body_size}
                class="input input-bordered input-sm"
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
                value={@policy.max_header_size}
                class="input input-bordered input-sm"
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
                value={@policy.max_uri_length}
                class="input input-bordered input-sm"
                min="1"
              />
            </div>
          </div>

          <div class="flex gap-2 pt-2">
            <button type="submit" class="btn btn-primary btn-sm">Update Policy</button>
            <.link navigate={show_path(@org, @project, @policy)} class="btn btn-ghost btn-sm">
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
end
