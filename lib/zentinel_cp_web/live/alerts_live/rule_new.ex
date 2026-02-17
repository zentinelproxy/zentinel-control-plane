defmodule ZentinelCpWeb.AlertsLive.RuleNew do
  use ZentinelCpWeb, :live_view

  import ZentinelCpWeb.SlosLive.Helpers

  alias ZentinelCp.{Audit, Events, Observability, Projects}
  alias ZentinelCp.Observability.AlertRule

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        slos = Observability.list_slos(project.id)
        channels = Events.list_channels(project.id)

        {:ok,
         assign(socket,
           page_title: "New Alert Rule - #{project.name}",
           org: org,
           project: project,
           slos: slos,
           channels: channels,
           selected_type: "metric"
         )}
    end
  end

  @impl true
  def handle_event("change_type", %{"rule_type" => type}, socket) do
    {:noreply, assign(socket, :selected_type, type)}
  end

  @impl true
  def handle_event("create_rule", params, socket) do
    project = socket.assigns.project
    condition = build_condition(params["rule_type"], params)

    channel_ids =
      case params["channel_ids"] do
        nil -> []
        ids when is_list(ids) -> ids
        id when is_binary(id) -> [id]
      end

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      rule_type: params["rule_type"],
      condition: condition,
      severity: params["severity"] || "warning",
      for_seconds: parse_int(params["for_seconds"], 0),
      channel_ids: channel_ids
    }

    case Observability.create_alert_rule(attrs) do
      {:ok, rule} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "create",
          "alert_rule",
          rule.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Alert rule created.")
         |> push_navigate(to: alert_rule_path(socket.assigns.org, project, rule))}

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
      <h1 class="text-xl font-bold">New Alert Rule</h1>

      <.k8s_section>
        <form phx-submit="create_rule" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              placeholder="e.g. High Error Rate"
              class="input input-bordered input-sm w-full"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              class="textarea textarea-bordered textarea-sm w-full"
              rows="2"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Rule Type</span></label>
            <select
              name="rule_type"
              required
              class="select select-bordered select-sm w-full"
              phx-change="change_type"
            >
              <option :for={type <- AlertRule.rule_types()} value={type}>{type}</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Severity</span></label>
            <select name="severity" class="select select-bordered select-sm w-full">
              <option :for={sev <- AlertRule.severities()} value={sev}>{sev}</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Grace Period (seconds)</span>
            </label>
            <input
              type="number"
              name="for_seconds"
              value="0"
              min="0"
              class="input input-bordered input-sm w-full"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                How long the condition must persist before firing (0 = immediate).
              </span>
            </label>
          </div>

          <div class="space-y-4 ml-4 p-3 border-l-2 border-primary/30">
            <p class="text-xs font-semibold text-base-content/70">Condition</p>

            <div :if={@selected_type in ["metric", "threshold"]} class="space-y-3">
              <div class="form-control">
                <label class="label"><span class="label-text">Metric</span></label>
                <select name="metric" class="select select-bordered select-sm w-full">
                  <option value="error_rate">Error Rate</option>
                  <option value="latency_p99">Latency P99</option>
                  <option value="latency_p95">Latency P95</option>
                  <option value="request_count">Request Count</option>
                </select>
              </div>

              <div class="grid grid-cols-2 gap-2">
                <div class="form-control">
                  <label class="label"><span class="label-text">Operator</span></label>
                  <select name="operator" class="select select-bordered select-sm w-full">
                    <option value=">">{">"}</option>
                    <option value=">=">>=</option>
                    <option value="<">{"<"}</option>
                    <option value="<=">{"<="}</option>
                    <option value="==">==</option>
                    <option value="!=">!=</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Value</span></label>
                  <input
                    type="number"
                    name="value"
                    step="any"
                    required
                    class="input input-bordered input-sm w-full"
                  />
                </div>
              </div>
            </div>

            <div :if={@selected_type == "slo"} class="space-y-3">
              <div class="form-control">
                <label class="label"><span class="label-text">SLO</span></label>
                <select name="slo_id" class="select select-bordered select-sm w-full">
                  <option value="">Select SLO...</option>
                  <option :for={slo <- @slos} value={slo.id}>{slo.name}</option>
                </select>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Burn Rate Threshold</span></label>
                <input
                  type="number"
                  name="burn_rate_threshold"
                  step="any"
                  placeholder="e.g. 2.0"
                  class="input input-bordered input-sm w-full"
                />
              </div>
            </div>
          </div>

          <div :if={@channels != []} class="form-control">
            <label class="label">
              <span class="label-text font-medium">Notification Channels</span>
            </label>
            <div class="space-y-1">
              <label :for={ch <- @channels} class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="channel_ids[]"
                  value={ch.id}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm">{ch.name}</span>
                <span class="badge badge-xs badge-outline">{ch.type}</span>
              </label>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Rule</button>
            <.link navigate={alert_rules_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp build_condition("metric", params) do
    %{
      "metric" => params["metric"] || "error_rate",
      "operator" => params["operator"] || ">",
      "value" => parse_float(params["value"])
    }
  end

  defp build_condition("threshold", params), do: build_condition("metric", params)

  defp build_condition("slo", params) do
    %{
      "slo_id" => params["slo_id"],
      "burn_rate_threshold" => parse_float(params["burn_rate_threshold"])
    }
  end

  defp build_condition(_, _params), do: %{}

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(val), do: val

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(val, _default), do: val
end
