defmodule ZentinelCpWeb.ApiKeysLive.Index do
  @moduledoc """
  LiveView for managing API keys.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Accounts, Audit, Projects}

  @available_scopes [
    {"nodes:read", "Read node information"},
    {"nodes:write", "Manage nodes (delete, update)"},
    {"bundles:read", "Read bundles and download"},
    {"bundles:write", "Create, assign, and revoke bundles"},
    {"rollouts:read", "View rollouts"},
    {"rollouts:write", "Create and manage rollouts"},
    {"api_keys:admin", "Manage API keys"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    api_keys = Accounts.list_api_keys_for_user(current_user.id)
    projects = Projects.list_projects()

    {:ok,
     assign(socket,
       page_title: "API Keys",
       api_keys: api_keys,
       projects: projects,
       available_scopes: @available_scopes,
       show_form: false,
       newly_created_key: nil
     )}
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, newly_created_key: nil)}
  end

  @impl true
  def handle_event("dismiss_key", _, socket) do
    {:noreply, assign(socket, newly_created_key: nil)}
  end

  @impl true
  def handle_event("create_api_key", params, socket) do
    current_user = socket.assigns.current_user

    scopes =
      case params["scopes"] do
        nil -> []
        scopes when is_list(scopes) -> scopes
        scope when is_binary(scope) -> [scope]
      end

    attrs = %{
      name: params["name"],
      scopes: scopes,
      user_id: current_user.id,
      project_id: empty_to_nil(params["project_id"]),
      expires_at: parse_expires_at(params["expires_at"])
    }

    case Accounts.create_api_key(attrs) do
      {:ok, api_key} ->
        Audit.log_user_action(current_user, "create", "api_key", api_key.id,
          metadata: %{name: api_key.name, scopes: api_key.scopes}
        )

        api_keys = Accounts.list_api_keys_for_user(current_user.id)

        {:noreply,
         socket
         |> assign(
           api_keys: api_keys,
           show_form: false,
           newly_created_key: api_key.key
         )
         |> put_flash(:info, "API key created. Copy it now - it won't be shown again!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    api_key = Accounts.get_api_key(id)

    if api_key && api_key.user_id == current_user.id do
      case Accounts.revoke_api_key(api_key) do
        {:ok, _} ->
          Audit.log_user_action(current_user, "revoke", "api_key", api_key.id,
            metadata: %{name: api_key.name}
          )

          api_keys = Accounts.list_api_keys_for_user(current_user.id)

          {:noreply,
           socket
           |> assign(api_keys: api_keys)
           |> put_flash(:info, "API key revoked.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not revoke API key.")}
      end
    else
      {:noreply, put_flash(socket, :error, "API key not found.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    api_key = Accounts.get_api_key(id)

    if api_key && api_key.user_id == current_user.id do
      case Accounts.delete_api_key(api_key) do
        {:ok, _} ->
          Audit.log_user_action(current_user, "delete", "api_key", api_key.id,
            metadata: %{name: api_key.name}
          )

          api_keys = Accounts.list_api_keys_for_user(current_user.id)

          {:noreply,
           socket
           |> assign(api_keys: api_keys)
           |> put_flash(:info, "API key deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete API key.")}
      end
    else
      {:noreply, put_flash(socket, :error, "API key not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">API Keys</h1>
        </:filters>
        <:actions>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New API Key
          </button>
        </:actions>
      </.table_toolbar>

      <div
        :if={@newly_created_key}
        class="alert alert-warning shadow-lg"
      >
        <div>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="stroke-current flex-shrink-0 h-6 w-6"
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
          <div>
            <h3 class="font-bold">Save your API key now!</h3>
            <p class="text-sm">This key will only be shown once. Copy it and store it securely.</p>
            <div class="mt-2 flex items-center gap-2">
              <code class="bg-base-100 px-3 py-2 rounded font-mono text-sm select-all">
                {@newly_created_key}
              </code>
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                onclick={"navigator.clipboard.writeText('#{@newly_created_key}')"}
              >
                Copy
              </button>
            </div>
          </div>
        </div>
        <button class="btn btn-sm btn-ghost" phx-click="dismiss_key">Dismiss</button>
      </div>

      <div :if={@show_form}>
        <.k8s_section title="Create API Key">
          <form phx-submit="create_api_key" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="name"
                  required
                  maxlength="100"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. CI/CD Pipeline"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Project (optional)</span></label>
                <select name="project_id" class="select select-bordered select-sm w-full">
                  <option value="">All projects</option>
                  <option :for={project <- @projects} value={project.id}>
                    {project.name}
                  </option>
                </select>
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Scope key to a specific project
                  </span>
                </label>
              </div>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Expires At (optional)</span></label>
              <input
                type="datetime-local"
                name="expires_at"
                class="input input-bordered input-sm w-full max-w-xs"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Leave empty for no expiration. Uses UTC timezone.
                </span>
              </label>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Permissions</span></label>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
                <label
                  :for={{scope, description} <- @available_scopes}
                  class="label cursor-pointer justify-start gap-3 p-2 rounded hover:bg-base-200"
                >
                  <input
                    type="checkbox"
                    name="scopes[]"
                    value={scope}
                    class="checkbox checkbox-sm"
                  />
                  <div>
                    <span class="label-text font-mono text-sm">{scope}</span>
                    <p class="text-xs text-base-content/50">{description}</p>
                  </div>
                </label>
              </div>
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Leave all unchecked for full access (not recommended).
                </span>
              </label>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">Create API Key</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
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
              <th class="text-xs uppercase">Key Prefix</th>
              <th class="text-xs uppercase">Project</th>
              <th class="text-xs uppercase">Scopes</th>
              <th class="text-xs uppercase">Status</th>
              <th class="text-xs uppercase">Last Used</th>
              <th class="text-xs uppercase">Created</th>
              <th class="text-xs uppercase"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={api_key <- @api_keys}>
              <td class="font-medium">{api_key.name}</td>
              <td class="font-mono text-sm">{api_key.key_prefix}•••</td>
              <td class="text-sm">
                {get_project_name(@projects, api_key.project_id)}
              </td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={scope <- api_key.scopes}
                    class="badge badge-xs badge-outline font-mono"
                  >
                    {scope}
                  </span>
                  <span :if={api_key.scopes == []} class="text-base-content/50 text-xs">
                    Full access
                  </span>
                </div>
              </td>
              <td><.status_badge api_key={api_key} /></td>
              <td class="text-sm">
                {format_datetime(api_key.last_used_at) || "Never"}
              </td>
              <td class="text-sm">{format_datetime(api_key.inserted_at)}</td>
              <td class="flex gap-1">
                <button
                  :if={is_nil(api_key.revoked_at)}
                  phx-click="revoke"
                  phx-value-id={api_key.id}
                  data-confirm="Are you sure you want to revoke this API key? It will immediately stop working."
                  class="btn btn-ghost btn-xs text-warning"
                >
                  Revoke
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={api_key.id}
                  data-confirm="Are you sure you want to permanently delete this API key?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@api_keys == []} class="text-center py-12 text-base-content/50">
          <p>No API keys yet.</p>
          <p class="mt-2 text-sm">
            Create an API key to access the Zentinel API programmatically.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    cond do
      assigns.api_key.revoked_at ->
        ~H"""
        <span class="badge badge-sm badge-error">Revoked</span>
        """

      assigns.api_key.expires_at &&
          DateTime.compare(assigns.api_key.expires_at, DateTime.utc_now()) == :lt ->
        ~H"""
        <span class="badge badge-sm badge-warning">Expired</span>
        """

      true ->
        ~H"""
        <span class="badge badge-sm badge-success">Active</span>
        """
    end
  end

  defp get_project_name(_projects, nil), do: "All"

  defp get_project_name(projects, project_id) do
    case Enum.find(projects, fn p -> p.id == project_id end) do
      nil -> "—"
      project -> project.name
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp parse_expires_at(nil), do: nil
  defp parse_expires_at(""), do: nil

  defp parse_expires_at(str) do
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
