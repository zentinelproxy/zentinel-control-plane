defmodule SentinelCpWeb.ServiceTemplatesLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        templates = Services.list_templates(project.id)

        {:ok,
         assign(socket,
           page_title: "Service Templates — #{project.name}",
           org: org,
           project: project,
           templates: templates
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    template = Services.get_template!(id)

    if template.is_builtin do
      {:noreply, put_flash(socket, :error, "Cannot delete built-in templates.")}
    else
      case Services.delete_template(template) do
        {:ok, _} ->
          templates = Services.list_templates(socket.assigns.project.id)
          {:noreply, socket |> assign(templates: templates) |> put_flash(:info, "Template deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete template.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name="Service Templates"
        resource_type="template"
        back_path={project_services_path(@org, @project)}
      >
        <:action>
          <.link navigate={new_template_path(@org, @project)} class="btn btn-primary btn-sm">
            New Template
          </.link>
        </:action>
      </.detail_header>

      <.k8s_section>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Name</th>
                <th>Category</th>
                <th>Version</th>
                <th>Type</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={t <- @templates}>
                <td>
                  <.link navigate={template_show_path(@org, @project, t)} class="link link-primary">
                    {t.name}
                  </.link>
                </td>
                <td><span class="badge badge-sm badge-outline">{t.category}</span></td>
                <td>v{t.version}</td>
                <td>
                  <span :if={t.is_builtin} class="badge badge-sm badge-info">built-in</span>
                  <span :if={!t.is_builtin} class="badge badge-sm badge-ghost">custom</span>
                </td>
                <td class="flex gap-1">
                  <.link navigate={template_show_path(@org, @project, t)} class="btn btn-ghost btn-xs">
                    Details
                  </.link>
                  <.link :if={!t.is_builtin} navigate={template_edit_path(@org, @project, t)} class="btn btn-ghost btn-xs">
                    Edit
                  </.link>
                  <button
                    :if={!t.is_builtin}
                    phx-click="delete"
                    phx-value-id={t.id}
                    data-confirm="Are you sure?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_services_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp project_services_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

  defp new_template_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates/new"

  defp new_template_path(nil, project),
    do: ~p"/projects/#{project.slug}/service-templates/new"

  defp template_show_path(%{slug: org_slug}, project, template),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates/#{template.id}"

  defp template_show_path(nil, project, template),
    do: ~p"/projects/#{project.slug}/service-templates/#{template.id}"

  defp template_edit_path(%{slug: org_slug}, project, template),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates/#{template.id}/edit"

  defp template_edit_path(nil, project, template),
    do: ~p"/projects/#{project.slug}/service-templates/#{template.id}/edit"
end
