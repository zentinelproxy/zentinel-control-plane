defmodule ZentinelCpWeb.WebhooksLive.Index do
  @moduledoc """
  LiveView for configuring GitHub webhook settings per project.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        webhook_url = build_webhook_url()
        webhook_secret = get_webhook_secret()

        {:ok,
         assign(socket,
           page_title: "Webhooks — #{project.name}",
           org: org,
           project: project,
           webhook_url: webhook_url,
           webhook_secret_configured: webhook_secret != nil and webhook_secret != "",
           show_form: false,
           form: to_form(project_to_form(project), as: "webhook")
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("save", %{"webhook" => params}, socket) do
    project = socket.assigns.project

    attrs = %{
      github_repo: empty_to_nil(params["github_repo"]),
      github_branch: params["github_branch"] || "main",
      config_path: params["config_path"] || "zentinel.kdl"
    }

    case Projects.update_project(project, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(
           project: updated,
           show_form: false,
           form: to_form(project_to_form(updated), as: "webhook")
         )
         |> put_flash(:info, "Webhook settings updated.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "webhook"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">GitHub Webhooks</h1>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            {if @show_form, do: "Cancel", else: "Configure"}
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={!@webhook_secret_configured} class="alert alert-warning">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="stroke-current shrink-0 h-6 w-6"
          fill="none"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
          />
        </svg>
        <span>
          Webhook secret not configured. Set <code class="font-mono">GITHUB_WEBHOOK_SECRET</code>
          environment variable to enable webhook verification.
        </span>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Webhook Endpoint">
          <div class="space-y-4">
            <div>
              <div class="text-sm text-base-content/50 mb-1">Payload URL</div>
              <div class="flex items-center gap-2">
                <code class="bg-base-300 px-3 py-2 rounded font-mono text-sm flex-1 overflow-x-auto">
                  {@webhook_url}
                </code>
                <button
                  type="button"
                  class="btn btn-sm btn-ghost"
                  onclick={"navigator.clipboard.writeText('#{@webhook_url}')"}
                >
                  Copy
                </button>
              </div>
            </div>

            <div>
              <div class="text-sm text-base-content/50 mb-1">Content type</div>
              <code class="bg-base-300 px-3 py-2 rounded font-mono text-sm">application/json</code>
            </div>

            <div>
              <div class="text-sm text-base-content/50 mb-1">Events</div>
              <span class="badge badge-outline">push</span>
            </div>

            <div class="text-sm text-base-content/50">
              <p>Add this webhook URL to your GitHub repository settings.</p>
              <p class="mt-1">
                Go to <strong>Settings → Webhooks → Add webhook</strong> in your repository.
              </p>
            </div>
          </div>
        </.k8s_section>

        <.k8s_section title="Current Configuration">
          <.definition_list>
            <:item label="GitHub Repository">
              <span :if={@project.github_repo} class="font-mono">{@project.github_repo}</span>
              <span :if={!@project.github_repo} class="text-base-content/50">Not configured</span>
            </:item>
            <:item label="Branch">
              <span class="font-mono">{@project.github_branch || "main"}</span>
            </:item>
            <:item label="Config Path">
              <span class="font-mono">{@project.config_path || "zentinel.kdl"}</span>
            </:item>
            <:item label="Status">
              <span :if={@project.github_repo} class="badge badge-success badge-sm">Enabled</span>
              <span :if={!@project.github_repo} class="badge badge-ghost badge-sm">Disabled</span>
            </:item>
          </.definition_list>
        </.k8s_section>
      </div>

      <div :if={@show_form}>
        <.k8s_section title="Configure GitHub Integration">
          <form phx-submit="save" class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">GitHub Repository</span>
              </label>
              <input
                type="text"
                name="webhook[github_repo]"
                value={@form[:github_repo].value}
                class="input input-bordered input-sm w-full"
                placeholder="owner/repository (e.g. acme/zentinel-configs)"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Full repository name including owner. Leave empty to disable webhook integration.
                </span>
              </label>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Branch</span>
                </label>
                <input
                  type="text"
                  name="webhook[github_branch]"
                  value={@form[:github_branch].value || "main"}
                  class="input input-bordered input-sm w-full"
                  placeholder="main"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Only pushes to this branch trigger bundle creation.
                  </span>
                </label>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Config Path</span>
                </label>
                <input
                  type="text"
                  name="webhook[config_path]"
                  value={@form[:config_path].value || "zentinel.kdl"}
                  class="input input-bordered input-sm w-full"
                  placeholder="zentinel.kdl"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Path to the Zentinel config file in the repository.
                  </span>
                </label>
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">Save Configuration</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <.k8s_section title="How It Works">
        <div class="prose prose-sm max-w-none">
          <ol class="list-decimal list-inside space-y-2 text-sm">
            <li>Configure the GitHub repository and branch above</li>
            <li>Add the webhook URL to your GitHub repository settings</li>
            <li>Set the webhook secret in GitHub (must match <code>GITHUB_WEBHOOK_SECRET</code>)</li>
            <li>Push changes to your Zentinel config file</li>
            <li>A new bundle is automatically created and compiled</li>
          </ol>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp build_webhook_url do
    host = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:url][:host] || "localhost"
    scheme = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:url][:scheme] || "http"
    port = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:url][:port]

    port_str = if port in [nil, 80, 443], do: "", else: ":#{port}"
    "#{scheme}://#{host}#{port_str}/api/v1/webhooks/github"
  end

  defp get_webhook_secret do
    Application.get_env(:zentinel_cp, :github_webhook)[:secret]
  end

  defp project_to_form(project) do
    %{
      "github_repo" => project.github_repo,
      "github_branch" => project.github_branch || "main",
      "config_path" => project.config_path || "zentinel.kdl"
    }
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
