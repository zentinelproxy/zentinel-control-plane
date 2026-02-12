defmodule SentinelCpWeb.ServiceTemplatesLive.Show do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => template_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         template when not is_nil(template) <- Services.get_template(template_id) do
      {:ok,
       assign(socket,
         page_title: "Template #{template.name} — #{project.name}",
         org: org,
         project: project,
         template: template
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    template = socket.assigns.template

    if template.is_builtin do
      {:noreply, put_flash(socket, :error, "Cannot delete built-in templates.")}
    else
      case Services.delete_template(template) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Template deleted.")
           |> push_navigate(to: templates_path(socket.assigns.org, socket.assigns.project))}

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
        name={@template.name}
        resource_type="template"
        back_path={templates_path(@org, @project)}
      >
        <:badge>
          <span class="badge badge-sm badge-outline">{@template.category}</span>
          <span :if={@template.is_builtin} class="badge badge-sm badge-info">built-in</span>
        </:badge>
        <:action>
          <.link
            :if={!@template.is_builtin}
            navigate={template_edit_path(@org, @project, @template)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <.link
            navigate={create_from_template_path(@org, @project, @template)}
            class="btn btn-primary btn-sm"
          >
            Create Service
          </.link>
          <button
            :if={!@template.is_builtin}
            phx-click="delete"
            data-confirm="Are you sure?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="Name">{@template.name}</:item>
            <:item label="Slug"><span class="font-mono">{@template.slug}</span></:item>
            <:item label="Description">{@template.description || "—"}</:item>
            <:item label="Category">{@template.category}</:item>
            <:item label="Version">v{@template.version}</:item>
            <:item label="Type">{if @template.is_builtin, do: "Built-in", else: "Custom"}</:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Template Data">
          <pre class="bg-base-300 p-4 rounded text-sm font-mono whitespace-pre-wrap overflow-x-auto">{format_template_data(@template.template_data)}</pre>
        </.k8s_section>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp templates_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates"

  defp templates_path(nil, project),
    do: ~p"/projects/#{project.slug}/service-templates"

  defp template_edit_path(%{slug: org_slug}, project, template),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/service-templates/#{template.id}/edit"

  defp template_edit_path(nil, project, template),
    do: ~p"/projects/#{project.slug}/service-templates/#{template.id}/edit"

  defp create_from_template_path(%{slug: org_slug}, project, template),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/new?template_id=#{template.id}"

  defp create_from_template_path(nil, project, template),
    do: ~p"/projects/#{project.slug}/services/new?template_id=#{template.id}"

  defp format_template_data(nil), do: "—"
  defp format_template_data(data) when data == %{}, do: "—"

  defp format_template_data(data) do
    Jason.encode!(data, pretty: true)
  end
end
