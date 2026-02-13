defmodule SentinelCpWeb.SecretsLive.Index do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Orgs, Projects, Secrets}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        secrets = Secrets.list_secrets(project.id)

        {:ok,
         assign(socket,
           page_title: "Secrets — #{project.name}",
           org: org,
           project: project,
           secrets: secrets,
           show_form: false,
           editing: nil,
           form: new_form(),
           delete_confirm: nil
         )}
    end
  end

  @impl true
  def handle_event("show_form", _, socket) do
    {:noreply, assign(socket, show_form: true, editing: nil, form: new_form())}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, show_form: false, editing: nil, form: new_form())}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    secret = Secrets.get_secret!(id)

    form =
      to_form(
        %{
          "name" => secret.name,
          "value" => "",
          "description" => secret.description || "",
          "environment" => secret.environment || ""
        },
        as: "secret"
      )

    {:noreply, assign(socket, show_form: true, editing: secret, form: form)}
  end

  @impl true
  def handle_event("save", %{"secret" => params}, socket) do
    project = socket.assigns.project

    if socket.assigns.editing do
      update_secret(socket, params)
    else
      create_secret(socket, project, params)
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, delete_confirm: id)}
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, delete_confirm: nil)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    secret = Secrets.get_secret!(id)

    case Secrets.delete_secret(secret) do
      {:ok, _} ->
        secrets = Secrets.list_secrets(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(secrets: secrets, delete_confirm: nil)
         |> put_flash(:info, "Secret \"#{secret.name}\" deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete secret.")}
    end
  end

  defp create_secret(socket, project, params) do
    attrs = %{
      name: params["name"],
      value: params["value"],
      description: empty_to_nil(params["description"]),
      environment: empty_to_nil(params["environment"]),
      project_id: project.id
    }

    case Secrets.create_secret(attrs) do
      {:ok, _secret} ->
        secrets = Secrets.list_secrets(project.id)

        {:noreply,
         socket
         |> assign(secrets: secrets, show_form: false, form: new_form())
         |> put_flash(:info, "Secret \"#{attrs.name}\" created.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset_to_map(changeset), as: "secret"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  defp update_secret(socket, params) do
    secret = socket.assigns.editing

    attrs =
      %{description: empty_to_nil(params["description"])}
      |> maybe_put_value(params["value"])

    case Secrets.update_secret(secret, attrs) do
      {:ok, _updated} ->
        secrets = Secrets.list_secrets(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(secrets: secrets, show_form: false, editing: nil, form: new_form())
         |> put_flash(:info, "Secret \"#{secret.name}\" updated.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset_to_map(changeset), as: "secret"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Secrets</h1>
        </:filters>
        <:actions>
          <button :if={!@show_form} class="btn btn-primary btn-sm" phx-click="show_form">
            Create Secret
          </button>
          <button :if={@show_form} class="btn btn-ghost btn-sm" phx-click="cancel">
            Cancel
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={if @editing, do: "Edit Secret", else: "Create Secret"}>
          <form phx-submit="save" class="space-y-4">
            <div :if={!@editing} class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="secret[name]"
                value={@form[:name].value}
                class="input input-bordered input-sm w-full"
                placeholder="DATABASE_PASSWORD"
                required
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">
                  Letters, numbers, and underscores only. Used as {"${secrets.NAME}"} in configs.
                </span>
              </label>
            </div>

            <div :if={@editing} class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                value={@editing.name}
                class="input input-bordered input-sm w-full bg-base-200"
                disabled
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Value</span></label>
              <input
                type="password"
                name="secret[value]"
                class="input input-bordered input-sm w-full"
                placeholder={if @editing, do: "Leave empty to keep current value", else: "Secret value"}
                required={!@editing}
              />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Description</span></label>
                <input
                  type="text"
                  name="secret[description]"
                  value={@form[:description].value}
                  class="input input-bordered input-sm w-full"
                  placeholder="Optional description"
                />
              </div>
              <div :if={!@editing} class="form-control">
                <label class="label"><span class="label-text">Environment</span></label>
                <input
                  type="text"
                  name="secret[environment]"
                  value={@form[:environment].value}
                  class="input input-bordered input-sm w-full"
                  placeholder="All environments (leave empty)"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Scope to a specific environment, or leave empty for all.
                  </span>
                </label>
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing, do: "Update Secret", else: "Create Secret"}
              </button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <.k8s_section title="Project Secrets">
        <table :if={@secrets != []} class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Environment</th>
              <th class="text-xs uppercase">Description</th>
              <th class="text-xs uppercase">Last Rotated</th>
              <th class="text-xs uppercase">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={secret <- @secrets}>
              <td class="font-mono text-sm">{secret.name}</td>
              <td>
                <span :if={secret.environment} class="badge badge-outline badge-sm">
                  {secret.environment}
                </span>
                <span :if={!secret.environment} class="text-base-content/50 text-sm">All</span>
              </td>
              <td class="text-sm text-base-content/70">{secret.description || "—"}</td>
              <td class="text-sm text-base-content/70">
                {if secret.last_rotated_at, do: format_datetime(secret.last_rotated_at), else: "Never"}
              </td>
              <td>
                <div :if={@delete_confirm == secret.id} class="flex gap-1">
                  <button class="btn btn-error btn-xs" phx-click="delete" phx-value-id={secret.id}>
                    Confirm
                  </button>
                  <button class="btn btn-ghost btn-xs" phx-click="cancel_delete">Cancel</button>
                </div>
                <div :if={@delete_confirm != secret.id} class="flex gap-1">
                  <button class="btn btn-ghost btn-xs" phx-click="edit" phx-value-id={secret.id}>
                    Edit
                  </button>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="confirm_delete"
                    phx-value-id={secret.id}
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@secrets == []} class="text-base-content/50 text-sm py-4">
          No secrets configured. Create one to get started.
        </div>
      </.k8s_section>

      <.k8s_section title="Usage">
        <div class="prose prose-sm max-w-none text-sm space-y-2">
          <p>
            Reference secrets in service configuration maps using
            <code>{"${secrets.NAME}"}</code> syntax.
          </p>
          <p>
            Secrets are resolved at bundle compile time. They are never stored in plaintext in bundles.
          </p>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp new_form do
    to_form(%{"name" => "", "value" => "", "description" => "", "environment" => ""}, as: "secret")
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp maybe_put_value(attrs, nil), do: attrs
  defp maybe_put_value(attrs, ""), do: attrs
  defp maybe_put_value(attrs, value), do: Map.put(attrs, :value, value)

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp changeset_to_map(changeset) do
    changeset.changes
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
