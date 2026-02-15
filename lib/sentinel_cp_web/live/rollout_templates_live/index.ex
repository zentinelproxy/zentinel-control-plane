defmodule SentinelCpWeb.RolloutTemplatesLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Rollouts}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        templates = Rollouts.list_templates(project.id)

        {:ok,
         assign(socket,
           page_title: "Rollout Templates — #{project.name}",
           org: org,
           project: project,
           templates: templates,
           show_form: false,
           editing_template: nil,
           form: to_form(%{}, as: "template")
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply,
     assign(socket,
       show_form: !socket.assigns.show_form,
       editing_template: nil,
       form: to_form(%{}, as: "template")
     )}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    template = Rollouts.get_template!(id)

    form_data = %{
      "name" => template.name,
      "description" => template.description || "",
      "target_type" => get_target_type(template.target_selector),
      "labels" => format_labels(template.target_selector),
      "node_ids" => format_node_ids(template.target_selector),
      "strategy" => template.strategy,
      "batch_size" => to_string(template.batch_size),
      "max_unavailable" => to_string(template.max_unavailable),
      "progress_deadline_seconds" => to_string(template.progress_deadline_seconds),
      "health_gates_heartbeat" =>
        Map.get(template.health_gates || %{}, "heartbeat_healthy", false),
      "health_gates_max_error_rate" =>
        Map.get(template.health_gates || %{}, "max_error_rate", ""),
      "health_gates_max_latency_ms" =>
        Map.get(template.health_gates || %{}, "max_latency_ms", ""),
      "auto_rollback" => template.auto_rollback || false,
      "rollback_threshold" => to_string(template.rollback_threshold || 50),
      "validation_period_seconds" => to_string(template.validation_period_seconds || 300)
    }

    {:noreply,
     assign(socket,
       show_form: true,
       editing_template: template,
       form: to_form(form_data, as: "template")
     )}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       show_form: false,
       editing_template: nil,
       form: to_form(%{}, as: "template")
     )}
  end

  @impl true
  def handle_event("create_template", %{"template" => params}, socket) do
    project = socket.assigns.project
    current_user = socket.assigns.current_user

    attrs = build_template_attrs(params, project.id, current_user)

    case Rollouts.create_template(attrs) do
      {:ok, _template} ->
        templates = Rollouts.list_templates(project.id)

        {:noreply,
         socket
         |> assign(templates: templates, show_form: false, form: to_form(%{}, as: "template"))
         |> put_flash(:info, "Template created successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "template"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("update_template", %{"template" => params}, socket) do
    template = socket.assigns.editing_template
    attrs = build_template_attrs(params, nil, nil)

    case Rollouts.update_template(template, attrs) do
      {:ok, _template} ->
        templates = Rollouts.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(
           templates: templates,
           show_form: false,
           editing_template: nil,
           form: to_form(%{}, as: "template")
         )
         |> put_flash(:info, "Template updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "template"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    template = Rollouts.get_template!(id)

    case Rollouts.delete_template(template) do
      {:ok, _} ->
        templates = Rollouts.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(templates: templates)
         |> put_flash(:info, "Template deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete template.")}
    end
  end

  @impl true
  def handle_event("set_default", %{"id" => id}, socket) do
    template = Rollouts.get_template!(id)

    case Rollouts.set_default_template(template) do
      {:ok, _} ->
        templates = Rollouts.list_templates(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(templates: templates)
         |> put_flash(:info, "Template set as default.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not set default template.")}
    end
  end

  @impl true
  def handle_event("clear_default", %{"id" => id}, socket) do
    template = Rollouts.get_template!(id)

    if template.is_default do
      Rollouts.clear_default_template(socket.assigns.project.id)
      templates = Rollouts.list_templates(socket.assigns.project.id)

      {:noreply,
       socket
       |> assign(templates: templates)
       |> put_flash(:info, "Default cleared.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Rollout Templates</h1>
        </:filters>
        <:actions>
          <.link navigate={rollouts_path(@org, @project)} class="btn btn-outline btn-sm">
            Back to Rollouts
          </.link>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Template
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={if @editing_template, do: "Edit Template", else: "Create Template"}>
          <form
            phx-submit={if @editing_template, do: "update_template", else: "create_template"}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="template[name]"
                  value={@form[:name].value}
                  required
                  maxlength="100"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. Production Rolling"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Description</span></label>
                <input
                  type="text"
                  name="template[description]"
                  value={@form[:description].value}
                  maxlength="500"
                  class="input input-bordered input-sm w-full"
                  placeholder="Optional description"
                />
              </div>
            </div>

            <div class="divider text-sm">Target Configuration</div>

            <div class="form-control">
              <label class="label"><span class="label-text">Target Type</span></label>
              <select
                name="template[target_type]"
                class="select select-bordered select-sm w-full max-w-xs"
              >
                <option
                  value=""
                  selected={is_nil(@form[:target_type].value) or @form[:target_type].value == ""}
                >
                  No default target (select at rollout time)
                </option>
                <option value="all" selected={@form[:target_type].value == "all"}>All nodes</option>
                <option value="labels" selected={@form[:target_type].value == "labels"}>
                  By labels
                </option>
                <option value="node_ids" selected={@form[:target_type].value == "node_ids"}>
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
                name="template[labels]"
                value={@form[:labels].value}
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="env=production,region=us-east"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Node IDs (comma-separated)</span></label>
              <input
                type="text"
                name="template[node_ids]"
                value={@form[:node_ids].value}
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="node-id-1,node-id-2"
              />
            </div>

            <div class="divider text-sm">Rollout Strategy</div>

            <div class="flex flex-wrap gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Strategy</span></label>
                <select name="template[strategy]" class="select select-bordered select-sm">
                  <option
                    value="rolling"
                    selected={@form[:strategy].value not in ["all_at_once", "blue_green", "canary"]}
                  >
                    Rolling
                  </option>
                  <option value="all_at_once" selected={@form[:strategy].value == "all_at_once"}>
                    All at once
                  </option>
                  <option value="blue_green" selected={@form[:strategy].value == "blue_green"}>
                    Blue-Green
                  </option>
                  <option value="canary" selected={@form[:strategy].value == "canary"}>
                    Canary
                  </option>
                </select>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Batch Size</span></label>
                <input
                  type="number"
                  name="template[batch_size]"
                  value={@form[:batch_size].value || "1"}
                  min="1"
                  class="input input-bordered input-sm w-24"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Max Unavailable</span></label>
                <input
                  type="number"
                  name="template[max_unavailable]"
                  value={@form[:max_unavailable].value || "0"}
                  min="0"
                  class="input input-bordered input-sm w-24"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Deadline (seconds)</span></label>
                <input
                  type="number"
                  name="template[progress_deadline_seconds]"
                  value={@form[:progress_deadline_seconds].value || "600"}
                  min="1"
                  class="input input-bordered input-sm w-28"
                />
              </div>
            </div>

            <div class="divider text-sm">Health Gates</div>

            <div class="flex flex-wrap gap-4">
              <div class="form-control">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="template[health_gates_heartbeat]"
                    value="true"
                    checked={@form[:health_gates_heartbeat].value in [true, "true"]}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">Require healthy heartbeat</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Max Error Rate (%)</span></label>
                <input
                  type="number"
                  name="template[health_gates_max_error_rate]"
                  value={@form[:health_gates_max_error_rate].value}
                  min="0"
                  max="100"
                  step="0.1"
                  class="input input-bordered input-sm w-24"
                  placeholder="e.g. 1.0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Max Latency (ms)</span></label>
                <input
                  type="number"
                  name="template[health_gates_max_latency_ms]"
                  value={@form[:health_gates_max_latency_ms].value}
                  min="0"
                  class="input input-bordered input-sm w-28"
                  placeholder="e.g. 500"
                />
              </div>
            </div>

            <div class="divider text-sm">Auto-Rollback</div>

            <div class="flex flex-wrap gap-4 items-end">
              <div class="form-control">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="template[auto_rollback]"
                    value="true"
                    checked={@form[:auto_rollback].value in [true, "true"]}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">Auto-rollback on failure</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Rollback Threshold (seconds)</span>
                </label>
                <input
                  type="number"
                  name="template[rollback_threshold]"
                  value={@form[:rollback_threshold].value || "50"}
                  min="1"
                  class="input input-bordered input-sm w-28"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Validation Period (seconds)</span>
                </label>
                <input
                  type="number"
                  name="template[validation_period_seconds]"
                  value={@form[:validation_period_seconds].value || "300"}
                  min="0"
                  class="input input-bordered input-sm w-28"
                />
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing_template, do: "Update Template", else: "Create Template"}
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
              <th class="text-xs uppercase">Strategy</th>
              <th class="text-xs uppercase">Batch Size</th>
              <th class="text-xs uppercase">Target</th>
              <th class="text-xs uppercase">Default</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={template <- @templates}>
              <td>
                <div class="flex items-center gap-2">
                  <.resource_badge type="template" />
                  <span class="font-medium">{template.name}</span>
                </div>
                <div :if={template.description} class="text-xs text-base-content/50 mt-1">
                  {template.description}
                </div>
              </td>
              <td class="text-sm">{template.strategy}</td>
              <td class="text-sm">{template.batch_size}</td>
              <td class="text-sm">{format_target(template.target_selector)}</td>
              <td>
                <span :if={template.is_default} class="badge badge-sm badge-success">default</span>
              </td>
              <td class="flex gap-1">
                <button
                  :if={!template.is_default}
                  phx-click="set_default"
                  phx-value-id={template.id}
                  class="btn btn-ghost btn-xs"
                >
                  Set Default
                </button>
                <button
                  :if={template.is_default}
                  phx-click="clear_default"
                  phx-value-id={template.id}
                  class="btn btn-ghost btn-xs"
                >
                  Clear Default
                </button>
                <button phx-click="edit" phx-value-id={template.id} class="btn btn-ghost btn-xs">
                  Edit
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={template.id}
                  data-confirm="Are you sure you want to delete this template?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@templates == []} class="text-center py-12 text-base-content/50">
          No rollout templates yet. Create one to save common rollout configurations.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp rollouts_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/rollouts"

  defp rollouts_path(nil, project),
    do: ~p"/projects/#{project.slug}/rollouts"

  defp build_template_attrs(params, project_id, current_user) do
    target_selector = build_target_selector(params)
    health_gates = build_health_gates(params)

    attrs = %{
      name: params["name"],
      description: params["description"],
      target_selector: target_selector,
      strategy: params["strategy"] || "rolling",
      batch_size: parse_int(params["batch_size"], 1),
      max_unavailable: parse_int(params["max_unavailable"], 0),
      progress_deadline_seconds: parse_int(params["progress_deadline_seconds"], 600),
      health_gates: health_gates,
      auto_rollback: params["auto_rollback"] in ["true", true],
      rollback_threshold: parse_int(params["rollback_threshold"], 50),
      validation_period_seconds: parse_int(params["validation_period_seconds"], 300)
    }

    attrs =
      if project_id do
        Map.put(attrs, :project_id, project_id)
      else
        attrs
      end

    if current_user do
      Map.put(attrs, :created_by_id, current_user.id)
    else
      attrs
    end
  end

  defp build_target_selector(params) do
    case params["target_type"] do
      "all" ->
        %{"type" => "all"}

      "labels" ->
        labels = parse_labels(params["labels"] || "")
        if map_size(labels) > 0, do: %{"type" => "labels", "labels" => labels}, else: nil

      "node_ids" ->
        ids = parse_node_ids(params["node_ids"] || "")
        if length(ids) > 0, do: %{"type" => "node_ids", "node_ids" => ids}, else: nil

      _ ->
        nil
    end
  end

  defp build_health_gates(params) do
    gates = %{}

    gates =
      if params["health_gates_heartbeat"] in ["true", true] do
        Map.put(gates, "heartbeat_healthy", true)
      else
        gates
      end

    gates =
      case parse_float(params["health_gates_max_error_rate"]) do
        nil -> gates
        val -> Map.put(gates, "max_error_rate", val)
      end

    gates =
      case parse_int(params["health_gates_max_latency_ms"], nil) do
        nil -> gates
        val -> Map.put(gates, "max_latency_ms", val)
      end

    if map_size(gates) > 0, do: gates, else: %{"heartbeat_healthy" => true}
  end

  defp get_target_type(nil), do: nil
  defp get_target_type(%{"type" => type}), do: type
  defp get_target_type(_), do: nil

  defp format_labels(nil), do: ""

  defp format_labels(%{"type" => "labels", "labels" => labels}) when is_map(labels) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_labels(_), do: ""

  defp format_node_ids(nil), do: ""

  defp format_node_ids(%{"type" => "node_ids", "node_ids" => ids}) when is_list(ids) do
    Enum.join(ids, ", ")
  end

  defp format_node_ids(_), do: ""

  defp format_target(nil), do: "Not set"
  defp format_target(%{"type" => "all"}), do: "All nodes"

  defp format_target(%{"type" => "labels", "labels" => labels}) do
    labels |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_target(%{"type" => "node_ids", "node_ids" => ids}) do
    "#{length(ids)} node(s)"
  end

  defp format_target(_), do: "Not set"

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
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(str) do
    case Float.parse(to_string(str)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
