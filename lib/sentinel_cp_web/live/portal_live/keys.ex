defmodule SentinelCpWeb.PortalLive.Keys do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Portal, Projects.Project}
  import SentinelCpWeb.PortalLive.Components

  @impl true
  def mount(%{"project_slug" => _slug}, _session, socket) do
    project = socket.assigns.portal_project

    # Portal keys require a logged-in user
    current_user = socket.assigns[:current_user]

    keys =
      if current_user do
        Portal.list_portal_keys(project.id, current_user.id)
      else
        []
      end

    {:ok,
     assign(socket,
       page_title: "API Keys — #{Project.portal_title(project)}",
       project: project,
       keys: keys,
       new_key_name: "",
       created_key: nil,
       has_user: current_user != nil
     ), layout: false}
  end

  @impl true
  def handle_event("create_key", %{"name" => name}, socket) do
    current_user = socket.assigns.current_user
    project = socket.assigns.project

    if current_user do
      case Portal.create_portal_key(project.id, name, current_user.id) do
        {:ok, key} ->
          keys = Portal.list_portal_keys(project.id, current_user.id)

          {:noreply,
           socket
           |> assign(keys: keys, created_key: key, new_key_name: "")
           |> put_flash(:info, "API key created.")}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, format_errors(changeset))}
      end
    else
      {:noreply, put_flash(socket, :error, "Login required to create API keys.")}
    end
  end

  @impl true
  def handle_event("dismiss_key", _, socket) do
    {:noreply, assign(socket, created_key: nil)}
  end

  @impl true
  def handle_event("revoke_key", %{"id" => key_id}, socket) do
    current_user = socket.assigns.current_user

    if current_user do
      case Portal.revoke_portal_key(key_id, current_user.id) do
        {:ok, _} ->
          keys = Portal.list_portal_keys(socket.assigns.project.id, current_user.id)

          {:noreply,
           socket
           |> assign(keys: keys)
           |> put_flash(:info, "API key revoked.")}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Key not found.")}

        {:error, :not_authorized} ->
          {:noreply, put_flash(socket, :error, "Not authorized.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Login required.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.portal_layout project={@project} current_path={"/portal/#{@project.slug}/keys"}>
      <div class="space-y-4">
        <h1 class="text-xl font-bold">API Keys</h1>

        <div :if={!@has_user} class="alert alert-warning">
          <span>You need to be logged in to manage API keys.</span>
        </div>

        <div :if={@created_key} class="alert alert-warning">
          <div class="w-full">
            <p class="font-bold">Save your API key now — it won't be shown again!</p>
            <code class="block mt-2 bg-base-300 p-2 rounded font-mono text-sm break-all">
              {@created_key.key}
            </code>
            <button class="btn btn-ghost btn-xs mt-2" phx-click="dismiss_key">Dismiss</button>
          </div>
        </div>

        <div :if={@has_user} class="card bg-base-200 p-4">
          <form phx-submit="create_key" class="flex gap-2 items-end">
            <div class="form-control flex-1">
              <label class="label"><span class="label-text">Key Name</span></label>
              <input
                type="text"
                name="name"
                value={@new_key_name}
                class="input input-bordered input-sm w-full"
                placeholder="my-api-key"
                required
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Create Key</button>
          </form>
          <p class="text-xs text-base-content/50 mt-2">
            Portal keys are scoped to read-only access for this project.
          </p>
        </div>

        <div :if={@has_user}>
          <table :if={@keys != []} class="table table-sm">
            <thead class="bg-base-200">
              <tr>
                <th class="text-xs uppercase">Name</th>
                <th class="text-xs uppercase">Key Prefix</th>
                <th class="text-xs uppercase">Created</th>
                <th class="text-xs uppercase">Last Used</th>
                <th class="text-xs uppercase">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={key <- @keys}>
                <td class="text-sm">{key.name}</td>
                <td class="font-mono text-sm">{key.key_prefix}...</td>
                <td class="text-sm text-base-content/60">
                  {Calendar.strftime(key.inserted_at, "%Y-%m-%d")}
                </td>
                <td class="text-sm text-base-content/60">
                  {if key.last_used_at, do: Calendar.strftime(key.last_used_at, "%Y-%m-%d %H:%M"), else: "Never"}
                </td>
                <td>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="revoke_key"
                    phx-value-id={key.id}
                  >
                    Revoke
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <div :if={@keys == []} class="text-base-content/50 text-sm py-4">
            No API keys yet. Create one to get started.
          </div>
        </div>
      </div>
    </.portal_layout>
    """
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
