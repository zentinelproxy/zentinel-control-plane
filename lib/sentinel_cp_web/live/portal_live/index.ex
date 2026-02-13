defmodule SentinelCpWeb.PortalLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Portal, Projects.Project}
  import SentinelCpWeb.PortalLive.Components

  @impl true
  def mount(%{"project_slug" => _slug}, _session, socket) do
    project = socket.assigns.portal_project
    specs = Portal.list_project_specs(project.id)

    {:ok,
     assign(socket,
       page_title: Project.portal_title(project),
       project: project,
       specs: specs
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.portal_layout project={@project} current_path={"/portal/#{@project.slug}"}>
      <div class="space-y-6">
        <div class="text-center py-8">
          <h1 class="text-3xl font-bold mb-2">{Project.portal_title(@project)}</h1>
          <p :if={Project.portal_description(@project)} class="text-base-content/60 max-w-2xl mx-auto">
            {Project.portal_description(@project)}
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <a
            href={~p"/portal/#{@project.slug}/docs"}
            class="card bg-base-200 hover:bg-base-300 transition-colors p-6 cursor-pointer"
          >
            <h3 class="font-bold text-lg mb-2">API Documentation</h3>
            <p class="text-sm text-base-content/60">
              Browse API endpoints, parameters, and response schemas.
            </p>
            <div :if={@specs != []} class="mt-3 text-sm text-base-content/50">
              {length(@specs)} spec(s) available
            </div>
          </a>

          <a
            href={~p"/portal/#{@project.slug}/console"}
            class="card bg-base-200 hover:bg-base-300 transition-colors p-6 cursor-pointer"
          >
            <h3 class="font-bold text-lg mb-2">API Console</h3>
            <p class="text-sm text-base-content/60">
              Test API endpoints interactively with a built-in request builder.
            </p>
          </a>

          <a
            href={~p"/portal/#{@project.slug}/keys"}
            class="card bg-base-200 hover:bg-base-300 transition-colors p-6 cursor-pointer"
          >
            <h3 class="font-bold text-lg mb-2">API Keys</h3>
            <p class="text-sm text-base-content/60">
              Manage your API keys for authenticating requests.
            </p>
          </a>
        </div>

        <div :if={@specs != []}>
          <h2 class="text-xl font-bold mb-4">Available APIs</h2>
          <div class="space-y-3">
            <a
              :for={spec <- @specs}
              href={~p"/portal/#{@project.slug}/docs/#{spec.id}"}
              class="block card bg-base-200 hover:bg-base-300 transition-colors p-4"
            >
              <div class="flex items-center justify-between">
                <div>
                  <span class="font-semibold">{spec.name}</span>
                  <span :if={spec.spec_version} class="badge badge-ghost badge-sm ml-2">
                    v{spec.spec_version}
                  </span>
                </div>
                <span class="text-sm text-base-content/50">
                  {spec.paths_count || 0} endpoints
                </span>
              </div>
            </a>
          </div>
        </div>
      </div>
    </.portal_layout>
    """
  end
end
