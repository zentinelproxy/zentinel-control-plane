defmodule ZentinelCpWeb.NodesLive.Index do
  @moduledoc """
  LiveView for listing and managing nodes.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Nodes, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => project_slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(project_slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "Project not found") |> redirect(to: ~p"/")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(ZentinelCp.PubSub, "nodes:#{project.id}")
          :timer.send_interval(10_000, self(), :refresh)
        end

        nodes = Nodes.list_nodes(project.id)
        stats = Nodes.get_node_stats(project.id)
        drift_stats = Nodes.get_drift_stats(project.id)
        environments = Projects.list_environments(project.id)

        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:project, project)
         |> assign(:nodes, nodes)
         |> assign(:stats, stats)
         |> assign(:drift_stats, drift_stats)
         |> assign(:environments, environments)
         |> assign(:status_filter, nil)
         |> assign(:environment_filter, nil)
         |> assign(:show_form, false)
         |> assign(:created_node_key, nil)
         |> assign(:page_title, "Nodes - #{project.name}")}
    end
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  @impl true
  def handle_params(params, _url, socket) do
    status_filter = params["status"]
    environment_filter = params["environment"]
    {:noreply, apply_filters(socket, status_filter, environment_filter)}
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, created_node_key: nil)}
  end

  def handle_event("dismiss_key", _, socket) do
    {:noreply, assign(socket, created_node_key: nil)}
  end

  def handle_event("create_node", params, socket) do
    project = socket.assigns.project

    labels =
      (params["labels"] || "")
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    attrs = %{
      project_id: project.id,
      name: params["name"],
      hostname: if(params["hostname"] != "", do: params["hostname"]),
      ip: if(params["ip"] != "", do: params["ip"]),
      version: if(params["version"] != "", do: params["version"]),
      labels: labels
    }

    case Nodes.register_node(attrs) do
      {:ok, node} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "node", node.id,
          project_id: project.id
        )

        nodes =
          filter_nodes(
            project.id,
            socket.assigns.status_filter,
            socket.assigns.environment_filter
          )

        stats = Nodes.get_node_stats(project.id)
        drift_stats = Nodes.get_drift_stats(project.id)

        {:noreply,
         socket
         |> assign(
           nodes: nodes,
           stats: stats,
           drift_stats: drift_stats,
           show_form: false,
           created_node_key: node.node_key
         )
         |> put_flash(:info, "Node registered.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)
          |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
          |> Enum.join("; ")

        {:noreply, put_flash(socket, :error, "Could not register node: #{errors}")}
    end
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status
    query = build_filter_query(status, socket.assigns.environment_filter)

    {:noreply,
     push_patch(socket, to: node_path(socket.assigns.org, socket.assigns.project, query))}
  end

  def handle_event("filter_environment", %{"environment" => environment}, socket) do
    environment = if environment == "", do: nil, else: environment
    query = build_filter_query(socket.assigns.status_filter, environment)

    {:noreply,
     push_patch(socket, to: node_path(socket.assigns.org, socket.assigns.project, query))}
  end

  def handle_event("filter", params, socket) do
    status = if params["status"] == "", do: nil, else: params["status"]
    environment = if params["environment"] == "", do: nil, else: params["environment"]

    query = [status: status, environment: environment] |> Enum.reject(fn {_, v} -> is_nil(v) end)

    {:noreply,
     push_patch(socket,
       to: node_path(socket.assigns.org, socket.assigns.project, query)
     )}
  end

  def handle_event(
        "assign_environment",
        %{"node-id" => node_id, "environment-id" => env_id},
        socket
      ) do
    env_id = if env_id == "", do: nil, else: env_id

    case Nodes.assign_node_to_environment(node_id, env_id) do
      {:ok, _node} ->
        nodes =
          filter_nodes(
            socket.assigns.project.id,
            socket.assigns.status_filter,
            socket.assigns.environment_filter
          )

        {:noreply,
         socket |> assign(:nodes, nodes) |> put_flash(:info, "Node environment updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update node environment.")}
    end
  end

  def handle_event("delete", %{"id" => node_id}, socket) do
    node = Nodes.get_node!(node_id)

    case Nodes.delete_node(node) do
      {:ok, _} ->
        nodes =
          filter_nodes(
            socket.assigns.project.id,
            socket.assigns.status_filter,
            socket.assigns.environment_filter
          )

        {:noreply, socket |> assign(:nodes, nodes) |> put_flash(:info, "Node deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete node")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    nodes =
      filter_nodes(
        socket.assigns.project.id,
        socket.assigns.status_filter,
        socket.assigns.environment_filter
      )

    stats = Nodes.get_node_stats(socket.assigns.project.id)
    drift_stats = Nodes.get_drift_stats(socket.assigns.project.id)
    {:noreply, assign(socket, nodes: nodes, stats: stats, drift_stats: drift_stats)}
  end

  @impl true
  def handle_info({:node_updated, _node}, socket) do
    nodes =
      filter_nodes(
        socket.assigns.project.id,
        socket.assigns.status_filter,
        socket.assigns.environment_filter
      )

    stats = Nodes.get_node_stats(socket.assigns.project.id)
    drift_stats = Nodes.get_drift_stats(socket.assigns.project.id)
    {:noreply, assign(socket, nodes: nodes, stats: stats, drift_stats: drift_stats)}
  end

  defp apply_filters(socket, status_filter, environment_filter) do
    # Resolve environment slug to ID
    env_id = resolve_environment_id(socket.assigns.environments, environment_filter)
    nodes = filter_nodes(socket.assigns.project.id, status_filter, env_id)

    assign(socket,
      nodes: nodes,
      status_filter: status_filter,
      environment_filter: environment_filter
    )
  end

  defp resolve_environment_id(_environments, nil), do: nil
  defp resolve_environment_id(_environments, "unassigned"), do: :unassigned

  defp resolve_environment_id(environments, slug) do
    case Enum.find(environments, fn e -> e.slug == slug end) do
      nil -> nil
      env -> env.id
    end
  end

  defp filter_nodes(project_id, status, environment_id) do
    opts = []
    opts = if status, do: [{:status, status} | opts], else: opts

    opts =
      case environment_id do
        nil -> opts
        :unassigned -> [{:environment_id, nil} | opts]
        id -> [{:environment_id, id} | opts]
      end

    if opts == [] do
      Nodes.list_nodes(project_id)
    else
      Nodes.list_nodes(project_id, opts)
    end
  end

  defp build_filter_query(status, environment) do
    []
    |> then(fn q -> if status, do: [{:status, status} | q], else: q end)
    |> then(fn q -> if environment, do: [{:environment, environment} | q], else: q end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-xl font-bold">Nodes</h1>

      <%!-- Node key banner --%>
      <div :if={@created_node_key} class="alert alert-warning">
        <div class="flex-1">
          <p class="font-semibold">Save this node key — it will not be shown again.</p>
          <pre class="mt-2 bg-base-300 p-3 rounded font-mono text-sm select-all">{@created_node_key}</pre>
        </div>
        <button class="btn btn-ghost btn-sm" phx-click="dismiss_key">Dismiss</button>
      </div>

      <.stat_strip>
        <:stat label="Total" value={to_string(Enum.count(@nodes))} color="info" testid="stats-total" />
        <:stat
          label="Online"
          value={to_string(Map.get(@stats, "online", 0))}
          color="success"
          testid="stats-online"
        />
        <:stat
          label="Offline"
          value={to_string(Map.get(@stats, "offline", 0))}
          color="error"
          testid="stats-offline"
        />
        <:stat
          label="Unknown"
          value={to_string(Map.get(@stats, "unknown", 0))}
          testid="stats-unknown"
        />
        <:stat
          label="Drifted"
          value={to_string(@drift_stats.drifted)}
          color={if @drift_stats.drifted > 0, do: "warning", else: nil}
          testid="stats-drifted"
        />
      </.stat_strip>

      <.table_toolbar>
        <:filters>
          <div class="flex gap-2">
            <form phx-change="filter_status">
              <select name="status" class="select select-bordered select-sm">
                <option value="">All statuses</option>
                <option value="online" selected={@status_filter == "online"}>Online</option>
                <option value="offline" selected={@status_filter == "offline"}>Offline</option>
                <option value="unknown" selected={@status_filter == "unknown"}>Unknown</option>
              </select>
            </form>
            <form :if={@environments != []} phx-change="filter_environment">
              <select name="environment" class="select select-bordered select-sm">
                <option value="">All environments</option>
                <option value="unassigned" selected={@environment_filter == "unassigned"}>
                  Unassigned
                </option>
                <option
                  :for={env <- @environments}
                  value={env.slug}
                  selected={@environment_filter == env.slug}
                >
                  {env.name}
                </option>
              </select>
            </form>
          </div>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            Register Node
          </button>
        </:actions>
      </.table_toolbar>

      <%!-- Create Node Form --%>
      <div :if={@show_form}>
        <.k8s_section title="Register Node">
          <form phx-submit="create_node" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="e.g. edge-node-01"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Alphanumeric, underscore, dot, or hyphen
                </span>
              </label>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Hostname</span></label>
                <input
                  type="text"
                  name="hostname"
                  class="input input-bordered input-sm w-full"
                  placeholder="optional"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">IP Address</span></label>
                <input
                  type="text"
                  name="ip"
                  class="input input-bordered input-sm w-full"
                  placeholder="optional"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Version</span></label>
                <input
                  type="text"
                  name="version"
                  class="input input-bordered input-sm w-full"
                  placeholder="optional"
                />
              </div>
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Labels (one key=value per line)</span>
              </label>
              <textarea
                name="labels"
                rows="3"
                class="textarea textarea-bordered textarea-sm font-mono text-sm w-full max-w-md"
                placeholder="env=production\nregion=us-east-1"
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Register</button>
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
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Status</th>
              <th :if={@environments != []} class="text-xs uppercase">Environment</th>
              <th class="text-xs uppercase">Config</th>
              <th class="text-xs uppercase">Version</th>
              <th class="text-xs uppercase">IP</th>
              <th class="text-xs uppercase">Last Seen</th>
              <th class="text-xs uppercase">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for node <- @nodes do %>
              <tr>
                <td>
                  <.link
                    navigate={node_show_path(@org, @project, node)}
                    class="flex items-center gap-2 text-primary hover:underline"
                  >
                    <.resource_badge type="node" />
                    {node.name}
                  </.link>
                </td>
                <td><.status_badge status={node.status} /></td>
                <td :if={@environments != []}>
                  <.environment_badge node={node} environments={@environments} />
                </td>
                <td><.config_status_badge node={node} /></td>
                <td class="font-mono text-sm">{node.version || "-"}</td>
                <td class="font-mono text-sm">{node.ip || "-"}</td>
                <td class="text-sm text-base-content/60">
                  {if node.last_seen_at, do: format_relative_time(node.last_seen_at), else: "Never"}
                </td>
                <td>
                  <button
                    phx-click="delete"
                    phx-value-id={node.id}
                    data-confirm="Are you sure you want to delete this node?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if Enum.empty?(@nodes) do %>
          <div class="p-8 text-center text-base-content/50" data-testid="empty-state">
            <p>No nodes found.</p>
            <p class="text-sm mt-2">Register a node above or let nodes self-register via the API.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {class, text} =
      case assigns.status do
        "online" -> {"badge-success", "Online"}
        "offline" -> {"badge-error", "Offline"}
        _ -> {"badge-ghost", "Unknown"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp config_status_badge(assigns) do
    {class, text} =
      cond do
        is_nil(assigns.node.expected_bundle_id) ->
          {"badge-ghost", "Unmanaged"}

        Nodes.node_drifted?(assigns.node) ->
          {"badge-warning", "Drifted"}

        true ->
          {"badge-success", "In Sync"}
      end

    assigns = assign(assigns, class: class, text: text)

    ~H"""
    <span class={"badge badge-sm #{@class}"}>{@text}</span>
    """
  end

  defp environment_badge(assigns) do
    env = Enum.find(assigns.environments, fn e -> e.id == assigns.node.environment_id end)
    assigns = assign(assigns, :env, env)

    ~H"""
    <span :if={@env} class="badge badge-sm" style={"background-color: #{@env.color}; color: white"}>
      {@env.name}
    </span>
    <span :if={!@env} class="text-base-content/50 text-sm">-</span>
    """
  end

  defp node_path(%{slug: org_slug}, project, query) do
    ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes?#{query}"
  end

  defp node_path(nil, project, query) do
    ~p"/projects/#{project.slug}/nodes?#{query}"
  end

  defp node_show_path(%{slug: org_slug}, project, node) do
    ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes/#{node.id}"
  end

  defp node_show_path(nil, project, node) do
    ~p"/projects/#{project.slug}/nodes/#{node.id}"
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
