defmodule SentinelCpWeb.RolloutsLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Rollouts, Bundles, Orgs, Projects}
  alias SentinelCp.Rollouts.RolloutTemplate

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(SentinelCp.PubSub, "rollouts:#{project.id}")
        end

        rollouts = Rollouts.list_rollouts(project.id)
        compiled_bundles = Bundles.list_bundles(project.id, status: "compiled")
        templates = Rollouts.list_templates(project.id)
        default_template = Rollouts.get_default_template(project.id)
        health_checks = Rollouts.list_health_check_endpoints(project.id)

        form_values =
          if default_template do
            template_to_form_values(default_template)
          else
            default_form_values()
          end

        {:ok,
         assign(socket,
           page_title: "Rollouts — #{project.name}",
           org: org,
           project: project,
           rollouts: rollouts,
           compiled_bundles: compiled_bundles,
           templates: templates,
           health_checks: health_checks,
           selected_template_id: default_template && default_template.id,
           form_values: form_values,
           show_form: false,
           selected_strategy: form_values.strategy
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("select_template", %{"template_id" => ""}, socket) do
    form_values = default_form_values()

    {:noreply,
     assign(socket,
       selected_template_id: nil,
       form_values: form_values,
       selected_strategy: form_values.strategy
     )}
  end

  @impl true
  def handle_event("select_template", %{"template_id" => template_id}, socket) do
    project = socket.assigns.project

    with template when not is_nil(template) <- Rollouts.get_template(template_id),
         true <- template.project_id == project.id do
      form_values = template_to_form_values(template)

      {:noreply,
       assign(socket,
         selected_template_id: template_id,
         form_values: form_values,
         selected_strategy: form_values.strategy
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Template not found.")}
    end
  end

  @impl true
  def handle_event("switch_strategy", %{"strategy" => strategy}, socket) do
    {:noreply, assign(socket, selected_strategy: strategy)}
  end

  @impl true
  def handle_event("create_rollout", params, socket) do
    project = socket.assigns.project
    current_user = socket.assigns.current_user

    target_selector =
      case params["target_type"] do
        "all" ->
          %{"type" => "all"}

        "labels" ->
          %{"type" => "labels", "labels" => parse_labels(params["labels"] || "")}

        "node_ids" ->
          %{"type" => "node_ids", "node_ids" => parse_node_ids(params["node_ids"] || "")}

        _ ->
          %{"type" => "all"}
      end

    scheduled_at = parse_scheduled_at(params["scheduled_at"])

    custom_health_checks =
      case params["custom_health_checks"] do
        nil -> []
        "" -> []
        ids when is_list(ids) -> ids
        id when is_binary(id) -> [id]
      end

    strategy = params["strategy"] || "rolling"

    canary_analysis_config =
      if strategy == "canary" do
        steps =
          (params["canary_steps"] || "5, 25, 50, 100")
          |> String.split(",", trim: true)
          |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))

        %{
          "error_rate_threshold" => parse_float(params["canary_error_threshold"], 5.0),
          "latency_p99_threshold_ms" => parse_float(params["canary_latency_threshold"], 500),
          "analysis_window_minutes" => parse_int(params["canary_window"], 5),
          "steps" => steps
        }
      else
        nil
      end

    attrs = %{
      project_id: project.id,
      bundle_id: params["bundle_id"],
      target_selector: target_selector,
      strategy: strategy,
      batch_size: parse_int(params["batch_size"], 1),
      batch_percentage: parse_int_or_nil(params["batch_percentage"]),
      auto_rollback: params["auto_rollback"] in ["true", true],
      rollback_threshold: parse_int(params["rollback_threshold"], 50),
      custom_health_checks: custom_health_checks,
      canary_analysis_config: canary_analysis_config,
      created_by_id: current_user && current_user.id,
      scheduled_at: scheduled_at
    }

    case Rollouts.create_rollout(attrs) do
      {:ok, rollout} ->
        # Submit for approval first
        {:ok, rollout} = Rollouts.submit_for_approval(rollout)

        # If scheduled, don't start immediately
        if rollout.scheduled_at do
          rollouts = Rollouts.list_rollouts(project.id)
          scheduled_time = Calendar.strftime(rollout.scheduled_at, "%Y-%m-%d %H:%M UTC")

          {:noreply,
           socket
           |> assign(rollouts: rollouts, show_form: false)
           |> put_flash(:info, "Rollout scheduled for #{scheduled_time}.")}
        else
          # Try to plan if approved or not required
          if Rollouts.can_start_rollout?(rollout) do
            case Rollouts.plan_rollout(rollout) do
              {:ok, _} ->
                rollouts = Rollouts.list_rollouts(project.id)

                {:noreply,
                 socket
                 |> assign(rollouts: rollouts, show_form: false)
                 |> put_flash(:info, "Rollout created and started.")}

              {:error, :no_target_nodes} ->
                {:noreply, put_flash(socket, :error, "No target nodes matched the selector.")}

              {:error, reason} ->
                {:noreply,
                 put_flash(socket, :error, "Failed to plan rollout: #{inspect(reason)}")}
            end
          else
            # Approval required
            rollouts = Rollouts.list_rollouts(project.id)

            {:noreply,
             socket
             |> assign(rollouts: rollouts, show_form: false)
             |> put_flash(:info, "Rollout created. Awaiting approval.")}
          end
        end

      {:error, :bundle_not_compiled} ->
        {:noreply, put_flash(socket, :error, "Bundle must be compiled before rollout.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed to create rollout: #{errors}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create rollout: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:rollout_updated, _rollout_id}, socket) do
    rollouts = Rollouts.list_rollouts(socket.assigns.project.id)
    {:noreply, assign(socket, rollouts: rollouts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Rollouts</h1>
        </:filters>
        <:actions>
          <.link navigate={templates_path(@org, @project)} class="btn btn-outline btn-sm">
            Manage Templates
          </.link>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Rollout
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title="Create Rollout">
          <form phx-submit="create_rollout" class="space-y-4">
            <div :if={@templates != []} class="form-control">
              <label class="label"><span class="label-text">Template</span></label>
              <select
                name="template_id"
                phx-change="select_template"
                class="select select-bordered select-sm w-full max-w-xs"
              >
                <option value="">No template</option>
                <option
                  :for={template <- @templates}
                  value={template.id}
                  selected={@selected_template_id == template.id}
                >
                  {template.name}{if template.is_default, do: " (default)", else: ""}
                </option>
              </select>
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Select a template to pre-fill rollout settings
                </span>
              </label>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Bundle</span></label>
              <select
                name="bundle_id"
                required
                class="select select-bordered select-sm w-full max-w-xs"
              >
                <option value="">Select a compiled bundle</option>
                <option :for={bundle <- @compiled_bundles} value={bundle.id}>
                  {bundle.version}
                </option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Target</span></label>
              <select name="target_type" class="select select-bordered select-sm w-full max-w-xs">
                <option value="all" selected={@form_values.target_type == "all"}>All nodes</option>
                <option value="labels" selected={@form_values.target_type == "labels"}>
                  By labels
                </option>
                <option value="node_ids" selected={@form_values.target_type == "node_ids"}>
                  Specific node IDs
                </option>
              </select>
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Labels (key=value, comma-separated)</span>
              </label>
              <input
                type="text"
                name="labels"
                value={@form_values.labels}
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="env=production,region=us-east"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Node IDs (comma-separated)</span></label>
              <input
                type="text"
                name="node_ids"
                value={@form_values.node_ids}
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="node-id-1,node-id-2"
              />
            </div>
            <div class="flex flex-wrap gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Strategy</span></label>
                <select
                  name="strategy"
                  phx-change="switch_strategy"
                  class="select select-bordered select-sm"
                >
                  <option value="rolling" selected={@selected_strategy == "rolling"}>
                    Rolling
                  </option>
                  <option value="all_at_once" selected={@selected_strategy == "all_at_once"}>
                    All at once
                  </option>
                  <option value="canary" selected={@selected_strategy == "canary"}>
                    Canary
                  </option>
                </select>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Batch Size</span></label>
                <input
                  type="number"
                  name="batch_size"
                  value={@form_values.batch_size}
                  min="1"
                  class="input input-bordered input-sm w-24"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Batch % (canary)</span></label>
                <input
                  type="number"
                  name="batch_percentage"
                  value={@form_values.batch_percentage}
                  min="1"
                  max="100"
                  placeholder="—"
                  class="input input-bordered input-sm w-24"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Override batch size with %
                  </span>
                </label>
              </div>
            </div>

            <div class="divider text-sm">Canary Settings</div>

            <div class="flex flex-wrap gap-4 items-end">
              <div class="form-control">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="auto_rollback"
                    value="true"
                    checked={@form_values.auto_rollback}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">Auto-rollback on failure</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Rollback Threshold %</span></label>
                <input
                  type="number"
                  name="rollback_threshold"
                  value={@form_values.rollback_threshold}
                  min="1"
                  max="100"
                  class="input input-bordered input-sm w-24"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Trigger rollback at this % failures
                  </span>
                </label>
              </div>
            </div>

            <div
              :if={@selected_strategy == "canary"}
              class="mt-4 p-4 border border-base-300 rounded-lg space-y-3"
              data-testid="canary-config"
            >
              <h3 class="text-sm font-semibold">Canary Analysis Configuration</h3>
              <div class="flex flex-wrap gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Error Rate Threshold %</span>
                  </label>
                  <input
                    type="number"
                    name="canary_error_threshold"
                    value="5.0"
                    step="0.1"
                    min="0"
                    class="input input-bordered input-sm w-28"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Latency P99 Threshold (ms)</span>
                  </label>
                  <input
                    type="number"
                    name="canary_latency_threshold"
                    value="500"
                    min="0"
                    class="input input-bordered input-sm w-28"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Analysis Window (min)</span>
                  </label>
                  <input
                    type="number"
                    name="canary_window"
                    value="5"
                    min="1"
                    class="input input-bordered input-sm w-24"
                  />
                </div>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-xs">Steps (% traffic, comma-separated)</span>
                </label>
                <input
                  type="text"
                  name="canary_steps"
                  value="5, 25, 50, 100"
                  class="input input-bordered input-sm w-64"
                  placeholder="5, 25, 50, 100"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Traffic percentages for progressive canary analysis
                  </span>
                </label>
              </div>
            </div>

            <div :if={@health_checks != []} class="form-control">
              <label class="label"><span class="label-text">Custom Health Checks</span></label>
              <select
                name="custom_health_checks[]"
                multiple
                class="select select-bordered select-sm w-full max-w-xs h-24"
              >
                <option
                  :for={hc <- @health_checks}
                  value={hc.id}
                  selected={hc.id in (@form_values.custom_health_checks || [])}
                >
                  {hc.name} ({hc.url})
                </option>
              </select>
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Hold Ctrl/Cmd to select multiple. Leave empty to use default health gates.
                </span>
              </label>
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Schedule (optional)</span>
              </label>
              <input
                type="datetime-local"
                name="scheduled_at"
                class="input input-bordered input-sm w-full max-w-xs"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Leave empty to start immediately. Uses UTC timezone.
                </span>
              </label>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create Rollout</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
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
              <th class="text-xs uppercase">ID</th>
              <th class="text-xs uppercase">State</th>
              <th class="text-xs uppercase">Bundle</th>
              <th class="text-xs uppercase">Strategy</th>
              <th class="text-xs uppercase">Target</th>
              <th class="text-xs uppercase">Started</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rollout <- @rollouts} data-testid="rollout-row">
              <td>
                <.link
                  navigate={rollout_show_path(@org, @project, rollout)}
                  class="flex items-center gap-2 text-primary hover:underline font-mono text-sm"
                >
                  <.resource_badge type="rollout" />
                  {String.slice(rollout.id, 0, 8)}
                </.link>
              </td>
              <td class="flex items-center gap-1">
                <span
                  class={[
                    "badge badge-sm",
                    rollout.state == "completed" && "badge-success",
                    rollout.state == "running" && "badge-warning",
                    rollout.state == "failed" && "badge-error",
                    rollout.state == "cancelled" && "badge-error",
                    rollout.state == "paused" && "badge-info",
                    rollout.state == "pending" && "badge-ghost"
                  ]}
                  data-testid="rollout-state"
                >
                  {rollout.state}
                </span>
                <span
                  :if={rollout.state == "pending" and rollout.approval_state == "pending_approval"}
                  class="badge badge-sm badge-warning"
                >
                  awaiting approval
                </span>
                <span
                  :if={rollout.state == "pending" and rollout.approval_state == "rejected"}
                  class="badge badge-sm badge-error"
                >
                  rejected
                </span>
                <span
                  :if={rollout.state == "pending" and rollout.scheduled_at}
                  class="badge badge-sm badge-info"
                  title={"Scheduled: #{Calendar.strftime(rollout.scheduled_at, "%Y-%m-%d %H:%M UTC")}"}
                >
                  scheduled
                </span>
              </td>
              <td class="font-mono text-sm">{rollout.bundle_id |> String.slice(0, 8)}</td>
              <td class="text-sm">{rollout.strategy}</td>
              <td class="text-sm">{format_target(rollout.target_selector)}</td>
              <td class="text-sm">
                {if rollout.started_at,
                  do: Calendar.strftime(rollout.started_at, "%Y-%m-%d %H:%M"),
                  else: "—"}
              </td>
              <td>
                <.link
                  navigate={rollout_show_path(@org, @project, rollout)}
                  class="btn btn-ghost btn-xs"
                >
                  Details
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@rollouts == []} class="text-center py-12 text-base-content/50">
          No rollouts yet. Create one to deploy a bundle.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp rollout_show_path(%{slug: org_slug}, project, rollout),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts/#{rollout.id}"

  defp rollout_show_path(nil, project, rollout),
    do: ~p"/projects/#{project.slug}/rollouts/#{rollout.id}"

  defp templates_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts/templates"

  defp templates_path(nil, project),
    do: ~p"/projects/#{project.slug}/rollouts/templates"

  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} node(s)"
  end

  defp format_target(_), do: "—"

  defp parse_labels(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_node_ids(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(nil, default), do: default
  defp parse_float("", default), do: default

  defp parse_float(str, default) do
    case Float.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_scheduled_at(nil), do: nil
  defp parse_scheduled_at(""), do: nil

  defp parse_scheduled_at(str) do
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  defp default_form_values do
    %{
      target_type: "all",
      labels: "",
      node_ids: "",
      strategy: "rolling",
      batch_size: 1,
      batch_percentage: nil,
      auto_rollback: false,
      rollback_threshold: 50,
      custom_health_checks: []
    }
  end

  defp template_to_form_values(%RolloutTemplate{} = template) do
    %{
      target_type: get_target_type(template.target_selector),
      labels: format_labels_for_input(template.target_selector),
      node_ids: format_node_ids_for_input(template.target_selector),
      strategy: template.strategy || "rolling",
      batch_size: template.batch_size || 1,
      batch_percentage: nil,
      auto_rollback: false,
      rollback_threshold: 50,
      custom_health_checks: []
    }
  end

  defp get_target_type(nil), do: "all"
  defp get_target_type(%{"type" => type}), do: type
  defp get_target_type(_), do: "all"

  defp format_labels_for_input(nil), do: ""

  defp format_labels_for_input(%{"type" => "labels", "labels" => labels}) when is_map(labels) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_labels_for_input(_), do: ""

  defp format_node_ids_for_input(nil), do: ""

  defp format_node_ids_for_input(%{"type" => "node_ids", "node_ids" => ids}) when is_list(ids) do
    Enum.join(ids, ", ")
  end

  defp format_node_ids_for_input(_), do: ""
end
