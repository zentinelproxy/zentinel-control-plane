defmodule ZentinelCpWeb.AuditLive.Index do
  @moduledoc """
  LiveView for viewing audit logs. Admin-only.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.Audit

  on_mount {ZentinelCpWeb.LiveHelpers, :require_admin}

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Audit.subscribe()

    socket =
      socket
      |> assign(page_title: "Audit Log")
      |> assign(page: 0)
      |> assign(filters: %{})
      |> load_logs()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters =
      %{
        action: params["action"],
        resource_type: params["resource_type"],
        actor_type: params["actor_type"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    page = parse_page(params["page"])

    socket =
      socket
      |> assign(page: page)
      |> assign(filters: filters)
      |> load_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{
        "action" => params["action"],
        "resource_type" => params["resource_type"],
        "actor_type" => params["actor_type"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/audit?#{query_params}")}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    params = Map.put(socket.assigns.filters, "page", page)
    {:noreply, push_patch(socket, to: ~p"/audit?#{params}")}
  end

  @impl true
  def handle_info({:audit_log_created, log_entry}, socket) do
    if matches_filters?(log_entry, socket.assigns.filters) and socket.assigns.page == 0 do
      logs = [log_entry | Enum.take(socket.assigns.logs, @per_page - 1)]
      {:noreply, assign(socket, logs: logs, total: socket.assigns.total + 1)}
    else
      {:noreply, assign(socket, total: socket.assigns.total + 1)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-xl font-bold">Audit Log</h1>

      <.table_toolbar>
        <:filters>
          <form phx-change="filter" class="flex gap-3">
            <select name="action" class="select select-bordered select-sm">
              <option value="">All actions</option>
              <%= for action <- @available_actions do %>
                <option value={action} selected={@filters[:action] == action}>{action}</option>
              <% end %>
            </select>

            <select name="resource_type" class="select select-bordered select-sm">
              <option value="">All resources</option>
              <%= for type <- @available_resource_types do %>
                <option value={type} selected={@filters[:resource_type] == type}>{type}</option>
              <% end %>
            </select>

            <select name="actor_type" class="select select-bordered select-sm">
              <option value="">All actors</option>
              <option value="user" selected={@filters[:actor_type] == "user"}>User</option>
              <option value="api_key" selected={@filters[:actor_type] == "api_key"}>API Key</option>
              <option value="system" selected={@filters[:actor_type] == "system"}>System</option>
              <option value="node" selected={@filters[:actor_type] == "node"}>Node</option>
            </select>
          </form>
        </:filters>
        <:actions>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-outline btn-sm">
              Export
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 9l-7 7-7-7"
                />
              </svg>
            </label>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-2 shadow bg-base-200 rounded-box w-40"
            >
              <li><a href={export_url(@filters, "json")} target="_blank">Export as JSON</a></li>
              <li><a href={export_url(@filters, "csv")} target="_blank">Export as CSV</a></li>
            </ul>
          </div>
        </:actions>
      </.table_toolbar>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Time</th>
              <th class="text-xs uppercase">Action</th>
              <th class="text-xs uppercase">Actor</th>
              <th class="text-xs uppercase">Resource</th>
              <th class="text-xs uppercase">Resource ID</th>
              <th class="text-xs uppercase">Project</th>
            </tr>
          </thead>
          <tbody>
            <%= for log <- @logs do %>
              <tr>
                <td class="text-sm text-base-content/60 whitespace-nowrap">
                  {Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td>
                  <span class={["badge badge-sm", action_badge_class(log.action)]}>
                    {log.action}
                  </span>
                </td>
                <td class="text-sm">
                  <span class="text-xs text-base-content/50">{log.actor_type}</span>
                  <br />
                  <span class="text-xs font-mono">{short_id(log.actor_id)}</span>
                </td>
                <td class="text-sm">{log.resource_type}</td>
                <td class="text-sm font-mono">{short_id(log.resource_id)}</td>
                <td class="text-sm font-mono">{short_id(log.project_id)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <div class="flex items-center justify-between">
        <p class="text-sm text-base-content/50">
          Showing {@page * @per_page + 1}-{min((@page + 1) * @per_page, @total)} of {@total}
        </p>
        <div class="flex gap-2">
          <%= if @page > 0 do %>
            <button
              phx-click="page"
              phx-value-page={@page - 1}
              class="btn btn-ghost btn-sm"
            >
              Previous
            </button>
          <% end %>
          <%= if (@page + 1) * @per_page < @total do %>
            <button
              phx-click="page"
              phx-value-page={@page + 1}
              class="btn btn-ghost btn-sm"
            >
              Next
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_logs(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page

    opts =
      [limit: @per_page, offset: page * @per_page]
      |> maybe_add_filter(:action, filters[:action])
      |> maybe_add_filter(:resource_type, filters[:resource_type])
      |> maybe_add_filter(:actor_type, filters[:actor_type])

    {logs, total} = Audit.list_all_audit_logs(opts)

    socket
    |> assign(logs: logs, total: total, per_page: @per_page)
    |> assign(available_actions: available_actions())
    |> assign(available_resource_types: available_resource_types())
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: [{key, value} | opts]

  defp matches_filters?(log_entry, filters) do
    Enum.all?(filters, fn
      {:action, action} -> log_entry.action == action
      {:resource_type, type} -> log_entry.resource_type == type
      {:actor_type, type} -> log_entry.actor_type == type
      _ -> true
    end)
  end

  defp parse_page(nil), do: 0

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, _} when n >= 0 -> n
      _ -> 0
    end
  end

  defp short_id(nil), do: "-"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8) <> "..."

  defp action_badge_class(action) do
    cond do
      String.contains?(action, "created") -> "badge-success"
      String.contains?(action, "deleted") -> "badge-error"
      String.contains?(action, "failed") -> "badge-error"
      String.contains?(action, "login") -> "badge-info"
      String.contains?(action, "logout") -> "badge-ghost"
      String.contains?(action, "revoked") -> "badge-warning"
      true -> "badge-ghost"
    end
  end

  defp available_actions do
    ~w(
      session.login session.logout
      bundle.created bundle.compiled bundle.compilation_failed
      bundle.downloaded bundle.assigned
      node.deleted
      rollout.created rollout.paused rollout.resumed
      rollout.cancelled rollout.rolled_back
      api_key.created api_key.revoked api_key.deleted
    )
  end

  defp available_resource_types do
    ~w(user bundle node rollout api_key)
  end

  defp export_url(filters, format) do
    params =
      filters
      |> Map.put(:format, format)
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    ~p"/audit/export?#{params}"
  end
end
