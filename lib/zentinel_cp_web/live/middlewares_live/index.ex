defmodule ZentinelCpWeb.MiddlewaresLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        middlewares = Services.list_middlewares(project.id)

        {:ok,
         assign(socket,
           page_title: "Middleware — #{project.name}",
           org: org,
           project: project,
           middlewares: middlewares
         )}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = socket.assigns.project

    with middleware when not is_nil(middleware) <- Services.get_middleware(id),
         true <- middleware.project_id == project.id do
      case Services.delete_middleware(middleware) do
        {:ok, _} ->
          Audit.log_user_action(
            socket.assigns.current_user,
            "delete",
            "middleware",
            middleware.id,
            project_id: project.id
          )

          middlewares = Services.list_middlewares(project.id)

          {:noreply,
           assign(socket, middlewares: middlewares) |> put_flash(:info, "Middleware deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete middleware.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Middleware not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold">Middleware</h1>
        <.link navigate={new_path(@org, @project)} class="btn btn-primary btn-sm">
          New Middleware
        </.link>
      </div>

      <.k8s_section>
        <table class="table table-sm">
          <thead>
            <tr>
              <th class="text-xs">Name</th>
              <th class="text-xs">Type</th>
              <th class="text-xs">Enabled</th>
              <th class="text-xs">Created</th>
              <th class="text-xs"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={mw <- @middlewares}>
              <td>
                <.link navigate={show_path(@org, @project, mw)} class="link link-primary">
                  {mw.name}
                </.link>
              </td>
              <td><span class="badge badge-sm badge-outline">{mw.middleware_type}</span></td>
              <td>
                <span class={["badge badge-xs", (mw.enabled && "badge-success") || "badge-ghost"]}>
                  {if mw.enabled, do: "yes", else: "no"}
                </span>
              </td>
              <td class="text-sm">{Calendar.strftime(mw.inserted_at, "%Y-%m-%d")}</td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={mw.id}
                  data-confirm="Are you sure you want to delete this middleware?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@middlewares == []} class="text-center py-8 text-base-content/50 text-sm">
          No middleware yet. Create one to build reusable proxy building blocks.
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp new_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/middlewares/new"

  defp new_path(nil, project),
    do: ~p"/projects/#{project.slug}/middlewares/new"

  defp show_path(%{slug: org_slug}, project, mw),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/middlewares/#{mw.id}"

  defp show_path(nil, project, mw),
    do: ~p"/projects/#{project.slug}/middlewares/#{mw.id}"
end
