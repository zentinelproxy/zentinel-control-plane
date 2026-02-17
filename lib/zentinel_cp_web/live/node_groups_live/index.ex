defmodule ZentinelCpWeb.NodeGroupsLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Nodes, Orgs, Projects}

  @colors [
    {"Indigo", "#6366f1"},
    {"Blue", "#3b82f6"},
    {"Cyan", "#06b6d4"},
    {"Teal", "#14b8a6"},
    {"Green", "#22c55e"},
    {"Yellow", "#eab308"},
    {"Orange", "#f97316"},
    {"Red", "#ef4444"},
    {"Pink", "#ec4899"},
    {"Purple", "#a855f7"}
  ]

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        groups = Nodes.list_node_groups(project.id)
        nodes = Nodes.list_nodes(project.id)

        {:ok,
         assign(socket,
           page_title: "Node Groups — #{project.name}",
           org: org,
           project: project,
           groups: groups,
           nodes: nodes,
           show_form: false,
           editing_group: nil,
           managing_members: nil,
           form: to_form(%{}, as: "group"),
           colors: @colors
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply,
     assign(socket,
       show_form: !socket.assigns.show_form,
       editing_group: nil,
       form: to_form(%{"color" => "#6366f1"}, as: "group")
     )}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    group = Nodes.get_node_group!(id)

    form_data = %{
      "name" => group.name,
      "description" => group.description || "",
      "color" => group.color || "#6366f1"
    }

    {:noreply,
     assign(socket,
       show_form: true,
       editing_group: group,
       form: to_form(form_data, as: "group")
     )}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       show_form: false,
       editing_group: nil,
       managing_members: nil,
       form: to_form(%{}, as: "group")
     )}
  end

  @impl true
  def handle_event("create_group", %{"group" => params}, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      color: params["color"]
    }

    case Nodes.create_node_group(attrs) do
      {:ok, _group} ->
        groups = Nodes.list_node_groups(project.id)

        {:noreply,
         socket
         |> assign(groups: groups, show_form: false, form: to_form(%{}, as: "group"))
         |> put_flash(:info, "Node group created successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "group"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("update_group", %{"group" => params}, socket) do
    group = socket.assigns.editing_group

    attrs = %{
      name: params["name"],
      description: params["description"],
      color: params["color"]
    }

    case Nodes.update_node_group(group, attrs) do
      {:ok, _group} ->
        groups = Nodes.list_node_groups(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(
           groups: groups,
           show_form: false,
           editing_group: nil,
           form: to_form(%{}, as: "group")
         )
         |> put_flash(:info, "Node group updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "group"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    group = Nodes.get_node_group!(id)

    case Nodes.delete_node_group(group) do
      {:ok, _} ->
        groups = Nodes.list_node_groups(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(groups: groups)
         |> put_flash(:info, "Node group deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete node group.")}
    end
  end

  @impl true
  def handle_event("manage_members", %{"id" => id}, socket) do
    group = Nodes.get_node_group!(id)
    {:noreply, assign(socket, managing_members: group)}
  end

  @impl true
  def handle_event("add_node", %{"node-id" => node_id}, socket) do
    group = socket.assigns.managing_members

    case Nodes.add_node_to_group(node_id, group.id) do
      {:ok, _} ->
        updated_group = Nodes.get_node_group!(group.id)
        groups = Nodes.list_node_groups(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(groups: groups, managing_members: updated_group)
         |> put_flash(:info, "Node added to group.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Node already in group.")}
    end
  end

  @impl true
  def handle_event("remove_node", %{"node-id" => node_id}, socket) do
    group = socket.assigns.managing_members

    Nodes.remove_node_from_group(node_id, group.id)
    updated_group = Nodes.get_node_group!(group.id)
    groups = Nodes.list_node_groups(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(groups: groups, managing_members: updated_group)
     |> put_flash(:info, "Node removed from group.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Node Groups</h1>
        </:filters>
        <:actions>
          <.link navigate={nodes_path(@org, @project)} class="btn btn-outline btn-sm">
            Back to Nodes
          </.link>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Group
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={if @editing_group, do: "Edit Group", else: "Create Group"}>
          <form
            phx-submit={if @editing_group, do: "update_group", else: "create_group"}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="group[name]"
                  value={@form[:name].value}
                  required
                  maxlength="100"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. Production US-East"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Color</span></label>
                <select name="group[color]" class="select select-bordered select-sm w-full">
                  <option
                    :for={{name, hex} <- @colors}
                    value={hex}
                    selected={@form[:color].value == hex}
                  >
                    {name}
                  </option>
                </select>
              </div>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="group[description]"
                value={@form[:description].value}
                maxlength="500"
                class="input input-bordered input-sm w-full"
                placeholder="Optional description"
              />
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing_group, do: "Update Group", else: "Create Group"}
              </button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div :if={@managing_members}>
        <.k8s_section title={"Manage Members — #{@managing_members.name}"}>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div>
              <h3 class="text-sm font-semibold mb-2">
                Current Members ({length(@managing_members.nodes)})
              </h3>
              <div class="space-y-1 max-h-64 overflow-y-auto">
                <div
                  :for={node <- @managing_members.nodes}
                  class="flex items-center justify-between p-2 bg-base-200 rounded"
                >
                  <span class="text-sm">{node.name}</span>
                  <button
                    phx-click="remove_node"
                    phx-value-node-id={node.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Remove
                  </button>
                </div>
                <div :if={@managing_members.nodes == []} class="text-sm text-base-content/50 p-2">
                  No nodes in this group yet.
                </div>
              </div>
            </div>
            <div>
              <h3 class="text-sm font-semibold mb-2">Available Nodes</h3>
              <div class="space-y-1 max-h-64 overflow-y-auto">
                <div
                  :for={node <- available_nodes(@nodes, @managing_members)}
                  class="flex items-center justify-between p-2 bg-base-200 rounded"
                >
                  <span class="text-sm">{node.name}</span>
                  <button
                    phx-click="add_node"
                    phx-value-node-id={node.id}
                    class="btn btn-ghost btn-xs text-success"
                  >
                    Add
                  </button>
                </div>
                <div
                  :if={available_nodes(@nodes, @managing_members) == []}
                  class="text-sm text-base-content/50 p-2"
                >
                  All nodes are in this group.
                </div>
              </div>
            </div>
          </div>
          <div class="mt-4">
            <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
              Done
            </button>
          </div>
        </.k8s_section>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Description</th>
              <th class="text-xs uppercase">Nodes</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={group <- @groups}>
              <td>
                <div class="flex items-center gap-2">
                  <span
                    class="w-3 h-3 rounded-full"
                    style={"background-color: #{group.color || "#6366f1"}"}
                  >
                  </span>
                  <span class="font-medium">{group.name}</span>
                </div>
              </td>
              <td class="text-sm text-base-content/70">{group.description || "-"}</td>
              <td>
                <span class="badge badge-sm badge-ghost">{length(group.nodes)} nodes</span>
              </td>
              <td class="flex gap-1">
                <button
                  phx-click="manage_members"
                  phx-value-id={group.id}
                  class="btn btn-ghost btn-xs"
                >
                  Members
                </button>
                <button phx-click="edit" phx-value-id={group.id} class="btn btn-ghost btn-xs">
                  Edit
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={group.id}
                  data-confirm="Are you sure you want to delete this group?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@groups == []} class="text-center py-12 text-base-content/50">
          No node groups yet. Create one to organize your nodes.
        </div>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp nodes_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes"

  defp nodes_path(nil, project),
    do: ~p"/projects/#{project.slug}/nodes"

  defp available_nodes(all_nodes, group) do
    member_ids = MapSet.new(group.nodes, & &1.id)
    Enum.reject(all_nodes, fn node -> MapSet.member?(member_ids, node.id) end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
