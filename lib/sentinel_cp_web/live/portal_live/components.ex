defmodule SentinelCpWeb.PortalLive.Components do
  @moduledoc """
  Shared UI components for the developer portal.
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: SentinelCpWeb.Endpoint, router: SentinelCpWeb.Router

  alias SentinelCp.Projects.Project

  attr :project, :map, required: true
  attr :current_path, :string, default: ""
  slot :inner_block, required: true

  def portal_layout(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <header class="bg-base-200 border-b border-base-300">
        <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <img
              :if={Project.portal_logo_url(@project)}
              src={Project.portal_logo_url(@project)}
              class="h-8"
              alt={Project.portal_title(@project)}
            />
            <span class="font-bold text-lg">{Project.portal_title(@project)}</span>
          </div>
          <nav class="flex items-center gap-4 text-sm">
            <.portal_nav_link
              href={~p"/portal/#{@project.slug}"}
              label="Home"
              active={@current_path == "/portal/#{@project.slug}"}
            />
            <.portal_nav_link
              href={~p"/portal/#{@project.slug}/docs"}
              label="Docs"
              active={String.contains?(@current_path, "/docs")}
            />
            <.portal_nav_link
              href={~p"/portal/#{@project.slug}/console"}
              label="Console"
              active={String.contains?(@current_path, "/console")}
            />
            <.portal_nav_link
              href={~p"/portal/#{@project.slug}/keys"}
              label="API Keys"
              active={String.contains?(@current_path, "/keys")}
            />
          </nav>
        </div>
      </header>
      <main class="max-w-7xl mx-auto px-4 py-6">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp portal_nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "px-3 py-1 rounded-md transition-colors",
        @active && "bg-primary text-primary-content",
        !@active && "hover:bg-base-300"
      ]}
    >
      {@label}
    </a>
    """
  end

  attr :method, :string, required: true

  def method_badge(assigns) do
    color =
      case assigns.method do
        "GET" -> "badge-success"
        "POST" -> "badge-info"
        "PUT" -> "badge-warning"
        "PATCH" -> "badge-warning"
        "DELETE" -> "badge-error"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-sm font-mono", @color]}>{@method}</span>
    """
  end
end
