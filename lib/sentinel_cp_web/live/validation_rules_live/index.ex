defmodule SentinelCpWeb.ValidationRulesLive.Index do
  @moduledoc """
  LiveView for managing config validation rules.
  """
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Bundles, Orgs, Projects}
  alias SentinelCp.Bundles.ConfigValidationRule

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        rules = Bundles.list_validation_rules(project.id)

        {:ok,
         assign(socket,
           page_title: "Validation Rules — #{project.name}",
           org: org,
           project: project,
           rules: rules,
           show_form: false,
           editing_rule: nil,
           form: to_form(%{}, as: "rule"),
           rule_types: ConfigValidationRule.rule_types(),
           severities: ConfigValidationRule.severities()
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply,
     assign(socket,
       show_form: !socket.assigns.show_form,
       editing_rule: nil,
       form: to_form(%{"severity" => "error", "enabled" => true}, as: "rule")
     )}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    rule = Bundles.get_validation_rule!(id)

    form_data = %{
      "name" => rule.name,
      "description" => rule.description || "",
      "rule_type" => rule.rule_type,
      "pattern" => rule.pattern || "",
      "severity" => rule.severity,
      "enabled" => rule.enabled,
      "max_bytes" => get_in(rule.config, ["max_bytes"]) || ""
    }

    {:noreply,
     assign(socket,
       show_form: true,
       editing_rule: rule,
       form: to_form(form_data, as: "rule")
     )}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       show_form: false,
       editing_rule: nil,
       form: to_form(%{}, as: "rule")
     )}
  end

  @impl true
  def handle_event("create_rule", %{"rule" => params}, socket) do
    project = socket.assigns.project

    attrs = build_rule_attrs(params, project.id)

    case Bundles.create_validation_rule(attrs) do
      {:ok, _rule} ->
        rules = Bundles.list_validation_rules(project.id)

        {:noreply,
         socket
         |> assign(rules: rules, show_form: false, form: to_form(%{}, as: "rule"))
         |> put_flash(:info, "Validation rule created successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "rule"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("update_rule", %{"rule" => params}, socket) do
    rule = socket.assigns.editing_rule
    attrs = build_rule_attrs(params, nil)

    case Bundles.update_validation_rule(rule, attrs) do
      {:ok, _rule} ->
        rules = Bundles.list_validation_rules(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(
           rules: rules,
           show_form: false,
           editing_rule: nil,
           form: to_form(%{}, as: "rule")
         )
         |> put_flash(:info, "Validation rule updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "rule"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = socket.assigns.project

    with rule when not is_nil(rule) <- Bundles.get_validation_rule(id),
         true <- rule.project_id == project.id do
      case Bundles.update_validation_rule(rule, %{enabled: !rule.enabled}) do
        {:ok, _rule} ->
          rules = Bundles.list_validation_rules(project.id)
          {:noreply, assign(socket, rules: rules)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not toggle rule.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Rule not found.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project

    with rule when not is_nil(rule) <- Bundles.get_validation_rule(id),
         true <- rule.project_id == project.id do
      case Bundles.delete_validation_rule(rule) do
        {:ok, _} ->
          rules = Bundles.list_validation_rules(project.id)

          {:noreply,
           socket
           |> assign(rules: rules)
           |> put_flash(:info, "Validation rule deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete rule.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Rule not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Config Validation Rules</h1>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Rule
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={if @editing_rule, do: "Edit Rule", else: "Create Rule"}>
          <form
            phx-submit={if @editing_rule, do: "update_rule", else: "create_rule"}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="rule[name]"
                  value={@form[:name].value}
                  required
                  maxlength="100"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. require-proxy-host"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Rule Type *</span></label>
                <select
                  name="rule[rule_type]"
                  required
                  class="select select-bordered select-sm w-full"
                >
                  <option value="">Select type</option>
                  <option
                    :for={type <- @rule_types}
                    value={type}
                    selected={@form[:rule_type].value == type}
                  >
                    {format_rule_type(type)}
                  </option>
                </select>
              </div>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="rule[description]"
                value={@form[:description].value}
                maxlength="200"
                class="input input-bordered input-sm w-full"
                placeholder="Explain what this rule validates"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Pattern / Field Name</span>
              </label>
              <input
                type="text"
                name="rule[pattern]"
                value={@form[:pattern].value}
                class="input input-bordered input-sm w-full font-mono"
                placeholder="e.g. proxy.host for required_field or ^admin$ for forbidden_pattern"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  For required_field: field path (e.g. "proxy.host"). For patterns: regex.
                </span>
              </label>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Max Size (bytes)</span>
              </label>
              <input
                type="number"
                name="rule[max_bytes]"
                value={@form[:max_bytes].value}
                min="1"
                class="input input-bordered input-sm w-48"
                placeholder="Only for max_size rule"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Only used for max_size rule type.
                </span>
              </label>
            </div>

            <div class="flex flex-wrap gap-4 items-end">
              <div class="form-control">
                <label class="label"><span class="label-text">Severity</span></label>
                <select name="rule[severity]" class="select select-bordered select-sm">
                  <option
                    :for={sev <- @severities}
                    value={sev}
                    selected={@form[:severity].value == sev}
                  >
                    {String.capitalize(sev)}
                  </option>
                </select>
              </div>
              <div class="form-control">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="rule[enabled]"
                    value="true"
                    checked={@form[:enabled].value in [true, "true"]}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">Enabled</span>
                </label>
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing_rule, do: "Update Rule", else: "Create Rule"}
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
              <th class="text-xs uppercase">Type</th>
              <th class="text-xs uppercase">Pattern</th>
              <th class="text-xs uppercase">Severity</th>
              <th class="text-xs uppercase">Enabled</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={rule <- @rules}>
              <td>
                <div class="font-medium">{rule.name}</div>
                <div :if={rule.description} class="text-xs text-base-content/50">
                  {rule.description}
                </div>
              </td>
              <td>
                <span class="badge badge-outline badge-sm">
                  {format_rule_type(rule.rule_type)}
                </span>
              </td>
              <td class="font-mono text-sm">{truncate(rule.pattern, 30)}</td>
              <td><.severity_badge severity={rule.severity} /></td>
              <td>
                <input
                  type="checkbox"
                  checked={rule.enabled}
                  phx-click="toggle_enabled"
                  phx-value-id={rule.id}
                  class="toggle toggle-sm"
                />
              </td>
              <td class="flex gap-1">
                <button phx-click="edit" phx-value-id={rule.id} class="btn btn-ghost btn-xs">
                  Edit
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={rule.id}
                  data-confirm="Are you sure you want to delete this rule?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@rules == []} class="text-center py-12 text-base-content/50">
          <p>No validation rules defined.</p>
          <p class="mt-2 text-sm">
            Create rules to validate bundle configurations before deployment.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp build_rule_attrs(params, project_id) do
    config =
      if params["max_bytes"] && params["max_bytes"] != "" do
        %{"max_bytes" => parse_int(params["max_bytes"], 0)}
      else
        %{}
      end

    attrs = %{
      name: params["name"],
      description: params["description"],
      rule_type: params["rule_type"],
      pattern: params["pattern"],
      severity: params["severity"] || "error",
      enabled: params["enabled"] in ["true", true],
      config: config
    }

    if project_id do
      Map.put(attrs, :project_id, project_id)
    else
      attrs
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end

  defp format_rule_type("required_field"), do: "Required Field"
  defp format_rule_type("forbidden_pattern"), do: "Forbidden Pattern"
  defp format_rule_type("allowed_pattern"), do: "Allowed Pattern"
  defp format_rule_type("max_size"), do: "Max Size"
  defp format_rule_type("json_schema"), do: "JSON Schema"
  defp format_rule_type(type), do: type

  defp truncate(nil, _), do: "—"
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "…"

  defp severity_badge(assigns) do
    class =
      case assigns.severity do
        "error" -> "badge-error"
        "warning" -> "badge-warning"
        "info" -> "badge-info"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@severity}</span>
    """
  end
end
