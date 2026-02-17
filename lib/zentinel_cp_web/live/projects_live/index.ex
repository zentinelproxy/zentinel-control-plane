defmodule ZentinelCpWeb.ProjectsLive.Index do
  @moduledoc """
  LiveView for listing and managing projects.
  Supports both org-scoped (/orgs/:org_slug/projects) and legacy (/projects) routes.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Projects, Orgs}

  @impl true
  def mount(params, _session, socket) do
    case params do
      %{"org_slug" => org_slug} ->
        mount_org_scoped(org_slug, socket)

      _ ->
        mount_legacy(socket)
    end
  end

  defp mount_org_scoped(org_slug, socket) do
    case Orgs.get_org_by_slug(org_slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      org ->
        projects = Projects.list_projects(org_id: org.id)

        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:projects, projects)
         |> assign(:show_form, false)
         |> assign(:editing_id, nil)
         |> assign(:page_title, "Projects — #{org.name}")}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  def handle_event("create_project", %{"name" => name, "description" => description}, socket) do
    org = socket.assigns.org

    case Projects.create_project(%{name: name, description: description, org_id: org.id}) do
      {:ok, project} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "project", project.id,
          org_id: org.id,
          project_id: project.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects, show_form: false)
         |> put_flash(:info, "Project created.")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not create project: #{format_errors(changeset)}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    {:noreply,
     assign(socket,
       editing_id: project.id,
       edit_name: project.name,
       edit_description: project.description || ""
     )}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("update_project", %{"name" => name, "description" => description}, socket) do
    project = Projects.get_project!(socket.assigns.editing_id)
    org = socket.assigns.org

    case Projects.update_project(project, %{name: name, description: description}) do
      {:ok, updated} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "project", updated.id,
          org_id: org.id,
          project_id: updated.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects, editing_id: nil)
         |> put_flash(:info, "Project updated.")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not update project: #{format_errors(changeset)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    org = socket.assigns.org

    case Projects.delete_project(project) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "project", project.id,
          org_id: org.id,
          project_id: project.id
        )

        projects = Projects.list_projects(org_id: org.id)

        {:noreply,
         socket
         |> assign(projects: projects)
         |> put_flash(:info, "Project deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete project.")}
    end
  end

  defp mount_legacy(socket) do
    user = socket.assigns.current_user
    orgs = Orgs.list_user_orgs(user.id)

    case orgs do
      [{org, _role}] ->
        {:ok, push_navigate(socket, to: ~p"/orgs/#{org.slug}/projects")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Projects</h1>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Project
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title="Create Project">
          <form phx-submit="create_project" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="e.g. my-project"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <textarea
                name="description"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full max-w-md"
                placeholder="Optional description"
              ></textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <%!-- Inline edit form for a project --%>
      <div :if={@editing_id}>
        <.k8s_section title="Edit Project">
          <form phx-submit="update_project" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                value={@edit_name}
                class="input input-bordered input-sm w-full max-w-xs"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <textarea
                name="description"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full max-w-md"
              >{@edit_description}</textarea>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
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
              <th class="text-xs uppercase">Description</th>
              <th class="text-xs uppercase">Slug</th>
              <th class="text-xs uppercase">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for project <- @projects do %>
              <tr>
                <td>
                  <.link
                    navigate={~p"/orgs/#{@org.slug}/projects/#{project.slug}/nodes"}
                    class="flex items-center gap-2 text-primary hover:underline"
                  >
                    <.resource_badge type="project" />
                    {project.name}
                  </.link>
                </td>
                <td class="text-sm text-base-content/60">{project.description || "—"}</td>
                <td class="font-mono text-sm text-base-content/50">{project.slug}</td>
                <td>
                  <div class="flex gap-1">
                    <button
                      phx-click="edit"
                      phx-value-id={project.id}
                      class="btn btn-ghost btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={project.id}
                      data-confirm="Are you sure you want to delete this project?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if Enum.empty?(@projects) do %>
          <div class="text-center py-8 text-base-content/50">
            <p>No projects yet.</p>
            <p class="text-sm mt-2">Create a project to get started.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
