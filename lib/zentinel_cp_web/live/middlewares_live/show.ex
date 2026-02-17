defmodule ZentinelCpWeb.MiddlewaresLive.Show do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug, "id" => middleware_id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         middleware when not is_nil(middleware) <- Services.get_middleware(middleware_id),
         true <- middleware.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Middleware #{middleware.name} — #{project.name}",
         org: org,
         project: project,
         middleware: middleware
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    middleware = socket.assigns.middleware
    project = socket.assigns.project
    org = socket.assigns.org

    case Services.delete_middleware(middleware) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "delete", "middleware", middleware.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Middleware deleted.")
         |> push_navigate(to: index_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete middleware.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@middleware.name}
        resource_type="middleware"
        back_path={index_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@middleware.enabled && "badge-success") || "badge-ghost"]}>
            {if @middleware.enabled, do: "enabled", else: "disabled"}
          </span>
        </:badge>
        <:action>
          <.link
            navigate={edit_path(@org, @project, @middleware)}
            class="btn btn-outline btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this middleware?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Details">
          <.definition_list>
            <:item label="ID"><span class="font-mono text-sm">{@middleware.id}</span></:item>
            <:item label="Name">{@middleware.name}</:item>
            <:item label="Slug"><span class="font-mono">{@middleware.slug}</span></:item>
            <:item label="Description">{@middleware.description || "—"}</:item>
            <:item label="Type">
              <span class="badge badge-sm badge-outline">{@middleware.middleware_type}</span>
            </:item>
            <:item label="Enabled">{if @middleware.enabled, do: "Yes", else: "No"}</:item>
            <:item label="Created">
              {Calendar.strftime(@middleware.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Configuration">
          <.definition_list>
            <:item :for={{key, value} <- Enum.sort(@middleware.config || %{})} label={key}>
              <span class="font-mono text-sm">{format_config_value(value)}</span>
            </:item>
          </.definition_list>
          <div
            :if={@middleware.config == nil || @middleware.config == %{}}
            class="text-center py-4 text-base-content/50 text-sm"
          >
            No configuration set.
          </div>
        </.k8s_section>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp index_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/middlewares"

  defp index_path(nil, project),
    do: ~p"/projects/#{project.slug}/middlewares"

  defp edit_path(%{slug: org_slug}, project, mw),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/middlewares/#{mw.id}/edit"

  defp edit_path(nil, project, mw),
    do: ~p"/projects/#{project.slug}/middlewares/#{mw.id}/edit"

  defp format_config_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_config_value(value) when is_list(value), do: inspect(value)
  defp format_config_value(value), do: to_string(value)
end
