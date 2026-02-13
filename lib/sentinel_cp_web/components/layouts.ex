defmodule SentinelCpWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SentinelCpWeb, :html

  alias SentinelCp.{Orgs, Projects}

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the current logged in user"
  attr :current_uri, :string, default: "", doc: "the current URI path"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:current_user, fn -> nil end)
      |> assign_new(:current_uri, fn -> "" end)

    if assigns.current_user do
      ~H"""
      <div class="k8s-layout bg-base-300">
        <.masthead current_user={@current_user} current_uri={@current_uri} />
        <div class="k8s-body">
          <.sidebar_nav current_uri={@current_uri} />
          <div class="k8s-content-wrapper">
            <main class="k8s-content bg-base-100 border border-base-300 rounded-lg">
              {render_slot(@inner_block)}
            </main>
          </div>
        </div>
      </div>
      <.flash_group flash={@flash} />
      """
    else
      ~H"""
      <main class="flex items-center justify-center min-h-screen bg-base-100">
        <div class="w-full max-w-md p-6">
          {render_slot(@inner_block)}
        </div>
      </main>
      <.flash_group flash={@flash} />
      """
    end
  end

  attr :current_user, :map, required: true
  attr :current_uri, :string, required: true

  defp masthead(assigns) do
    {org_name, org_slug, project_name, project_slug} = parse_context(assigns.current_uri)

    assigns =
      assign(assigns,
        org_name: org_name,
        org_slug: org_slug,
        project_name: project_name,
        project_slug: project_slug
      )

    ~H"""
    <header class="k8s-masthead bg-base-300 border-b border-base-300">
      <div class="flex items-center gap-2 flex-shrink-0">
        <img src={~p"/images/logo.svg"} width="28" />
        <span class="font-bold text-sm hidden sm:inline">Sentinel CP</span>
      </div>

      <div class="flex-1 flex items-center gap-1 text-sm text-base-content/60 min-w-0 overflow-hidden">
        <span :if={@org_name}>
          <.link navigate={~p"/orgs/#{@org_slug}/projects"} class="hover:text-base-content">
            {@org_name}
          </.link>
        </span>
        <span :if={@org_name && @project_name} class="text-base-content/30">/</span>
        <span :if={@project_name}>
          <.link
            navigate={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/nodes"}
            class="hover:text-base-content"
          >
            {@project_name}
          </.link>
        </span>
      </div>

      <div class="flex items-center gap-3 flex-shrink-0">
        <.theme_toggle />
        <span class="text-xs text-base-content/60 hidden sm:inline">{@current_user.email}</span>
        <.link
          href={~p"/session"}
          method="delete"
          class="text-xs text-base-content/50 hover:text-base-content"
        >
          Logout
        </.link>
      </div>
    </header>
    """
  end

  attr :current_uri, :string, required: true

  defp sidebar_nav(assigns) do
    {_org_name, org_slug, _project_name, project_slug} = parse_context(assigns.current_uri)
    has_project = org_slug != nil && project_slug != nil
    has_org = org_slug != nil
    path = URI.parse(assigns.current_uri).path || ""

    assigns =
      assign(assigns,
        org_slug: org_slug,
        project_slug: project_slug,
        has_project: has_project,
        has_org: has_org,
        path: path
      )

    ~H"""
    <nav class="k8s-sidebar bg-base-300">
      <div :if={@has_project}>
        <div class="sidebar-section-title">Workloads</div>
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/nodes"}
          icon="hero-server-stack"
          label="Nodes"
          current={@path}
          match="/nodes"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/services"}
          icon="hero-cog-6-tooth"
          label="Services"
          current={@path}
          match="/services"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/bundles"}
          icon="hero-cube"
          label="Bundles"
          current={@path}
          match="/bundles"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/rollouts"}
          icon="hero-arrow-path-rounded-square"
          label="Rollouts"
          current={@path}
          match="/rollouts"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/drift"}
          icon="hero-exclamation-triangle"
          label="Drift"
          current={@path}
          match="/drift"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/topology"}
          icon="hero-map"
          label="Topology"
          current={@path}
          match="/topology"
        />

        <div class="sidebar-section-title mt-4">Settings</div>
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/node-groups"}
          icon="hero-rectangle-group"
          label="Node Groups"
          current={@path}
          match="/node-groups"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/health-checks"}
          icon="hero-heart"
          label="Health Checks"
          current={@path}
          match="/health-checks"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/environments"}
          icon="hero-globe-alt"
          label="Environments"
          current={@path}
          match="/environments"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/webhooks"}
          icon="hero-link"
          label="Webhooks"
          current={@path}
          match="/webhooks"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects/#{@project_slug}/secrets"}
          icon="hero-lock-closed"
          label="Secrets"
          current={@path}
          match="/secrets"
        />
      </div>

      <div :if={@has_org}>
        <div class="sidebar-section-title">Organization</div>
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/dashboard"}
          icon="hero-squares-2x2"
          label="Dashboard"
          current={@path}
          match="/dashboard"
        />
        <.sidebar_link
          path={~p"/orgs/#{@org_slug}/projects"}
          icon="hero-folder"
          label="Projects"
          current={@path}
          match_exact={~p"/orgs/#{@org_slug}/projects"}
        />
      </div>

      <div>
        <div class="sidebar-section-title">Management</div>
        <.sidebar_link
          path={~p"/orgs"}
          icon="hero-building-office"
          label="Organizations"
          current={@path}
          match_exact={~p"/orgs"}
        />
        <.sidebar_link
          path={~p"/audit"}
          icon="hero-clipboard-document-list"
          label="Audit Log"
          current={@path}
          match="/audit"
        />
        <.sidebar_link
          path={~p"/api-keys"}
          icon="hero-key"
          label="API Keys"
          current={@path}
          match="/api-keys"
        />
        <.sidebar_link
          path={~p"/approvals"}
          icon="hero-check-badge"
          label="Approvals"
          current={@path}
          match="/approvals"
        />
        <.sidebar_link
          path={~p"/schedule"}
          icon="hero-calendar"
          label="Schedule"
          current={@path}
          match="/schedule"
        />
        <.sidebar_link
          path={~p"/profile"}
          icon="hero-user-circle"
          label="Profile"
          current={@path}
          match="/profile"
        />
      </div>
    </nav>
    """
  end

  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :current, :string, required: true
  attr :match, :string, default: nil
  attr :match_exact, :string, default: nil

  defp sidebar_link(assigns) do
    active =
      cond do
        assigns.match_exact -> assigns.current == assigns.match_exact
        assigns.match -> String.contains?(assigns.current, assigns.match)
        true -> false
      end

    assigns = assign(assigns, :active, active)

    ~H"""
    <.link navigate={@path} class={["sidebar-item", @active && "sidebar-item-active"]}>
      <.icon name={@icon} class="size-5 flex-shrink-0" />
      <span class="sidebar-label">{@label}</span>
    </.link>
    """
  end

  defp parse_context(uri) when is_binary(uri) do
    path = URI.parse(uri).path || ""
    parse_context_from_path(path)
  end

  defp parse_context(_), do: {nil, nil, nil, nil}

  defp parse_context_from_path(path) do
    org_match = Regex.run(~r{/orgs/([^/]+)}, path)
    project_match = Regex.run(~r{/projects/([^/]+)}, path)

    {org_slug, org_name} =
      case org_match do
        [_, slug] ->
          case Orgs.get_org_by_slug(slug) do
            nil -> {slug, slug}
            org -> {slug, org.name}
          end

        _ ->
          {nil, nil}
      end

    {project_slug, project_name} =
      case project_match do
        [_, slug] when org_slug != nil ->
          if slug in ~w(new diff) do
            {nil, nil}
          else
            case Projects.get_project_by_slug(slug) do
              nil -> {slug, slug}
              project -> {slug, project.name}
            end
          end

        _ ->
          {nil, nil}
      end

    {org_name, org_slug, project_name, project_slug}
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
