defmodule ZentinelCpWeb.EnvironmentsLive.Index do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Orgs, Projects}

  @colors [
    {"Green", "#22c55e"},
    {"Yellow", "#eab308"},
    {"Red", "#ef4444"},
    {"Blue", "#3b82f6"},
    {"Indigo", "#6366f1"},
    {"Purple", "#a855f7"},
    {"Pink", "#ec4899"},
    {"Orange", "#f97316"}
  ]

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        environments = Projects.list_environments(project.id)
        env_stats = Projects.get_environment_stats(project.id)

        {:ok,
         assign(socket,
           page_title: "Environments — #{project.name}",
           org: org,
           project: project,
           environments: environments,
           env_stats: env_stats,
           show_form: false,
           editing_environment: nil,
           form: to_form(%{}, as: "environment"),
           colors: @colors
         )}
    end
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    next_ordinal =
      case socket.assigns.environments do
        [] -> 0
        envs -> Enum.max_by(envs, & &1.ordinal).ordinal + 1
      end

    {:noreply,
     assign(socket,
       show_form: !socket.assigns.show_form,
       editing_environment: nil,
       form:
         to_form(%{"ordinal" => to_string(next_ordinal), "color" => "#6366f1"}, as: "environment")
     )}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    environment = Projects.get_environment!(id)

    form_data = %{
      "name" => environment.name,
      "description" => environment.description || "",
      "color" => environment.color || "#6366f1",
      "ordinal" => to_string(environment.ordinal),
      "approval_required" => get_in(environment.settings, ["approval_required"]) || false,
      "approvals_needed" => to_string(get_in(environment.settings, ["approvals_needed"]) || 1)
    }

    {:noreply,
     assign(socket,
       show_form: true,
       editing_environment: environment,
       form: to_form(form_data, as: "environment")
     )}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     assign(socket,
       show_form: false,
       editing_environment: nil,
       form: to_form(%{}, as: "environment")
     )}
  end

  @impl true
  def handle_event("create_environment", %{"environment" => params}, socket) do
    project = socket.assigns.project

    attrs = build_environment_attrs(params, project.id)

    case Projects.create_environment(attrs) do
      {:ok, _environment} ->
        environments = Projects.list_environments(project.id)
        env_stats = Projects.get_environment_stats(project.id)

        {:noreply,
         socket
         |> assign(
           environments: environments,
           env_stats: env_stats,
           show_form: false,
           form: to_form(%{}, as: "environment")
         )
         |> put_flash(:info, "Environment created successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "environment"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("update_environment", %{"environment" => params}, socket) do
    environment = socket.assigns.editing_environment
    attrs = build_environment_attrs(params, nil)

    case Projects.update_environment(environment, attrs) do
      {:ok, _environment} ->
        environments = Projects.list_environments(socket.assigns.project.id)
        env_stats = Projects.get_environment_stats(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(
           environments: environments,
           env_stats: env_stats,
           show_form: false,
           editing_environment: nil,
           form: to_form(%{}, as: "environment")
         )
         |> put_flash(:info, "Environment updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "environment"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    environment = Projects.get_environment!(id)
    node_count = Map.get(socket.assigns.env_stats, id, 0)

    if node_count > 0 do
      {:noreply, put_flash(socket, :error, "Cannot delete environment with assigned nodes.")}
    else
      case Projects.delete_environment(environment) do
        {:ok, _} ->
          environments = Projects.list_environments(socket.assigns.project.id)
          env_stats = Projects.get_environment_stats(socket.assigns.project.id)

          {:noreply,
           socket
           |> assign(environments: environments, env_stats: env_stats)
           |> put_flash(:info, "Environment deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete environment.")}
      end
    end
  end

  @impl true
  def handle_event("create_defaults", _, socket) do
    project = socket.assigns.project

    case Projects.create_default_environments(project.id) do
      {:ok, _envs} ->
        environments = Projects.list_environments(project.id)
        env_stats = Projects.get_environment_stats(project.id)

        {:noreply,
         socket
         |> assign(environments: environments, env_stats: env_stats)
         |> put_flash(:info, "Default environments created.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create default environments.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Environments</h1>
        </:filters>
        <:actions>
          <button
            :if={@environments == []}
            class="btn btn-outline btn-sm"
            phx-click="create_defaults"
          >
            Create Defaults
          </button>
          <button class="btn btn-primary btn-sm" phx-click="toggle_form">
            New Environment
          </button>
        </:actions>
      </.table_toolbar>

      <div :if={@show_form}>
        <.k8s_section title={
          if @editing_environment, do: "Edit Environment", else: "Create Environment"
        }>
          <form
            phx-submit={if @editing_environment, do: "update_environment", else: "create_environment"}
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name *</span></label>
                <input
                  type="text"
                  name="environment[name]"
                  value={@form[:name].value}
                  required
                  maxlength="50"
                  class="input input-bordered input-sm w-full"
                  placeholder="e.g. Production"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Color</span></label>
                <select name="environment[color]" class="select select-bordered select-sm w-full">
                  <option
                    :for={{name, hex} <- @colors}
                    value={hex}
                    selected={@form[:color].value == hex}
                  >
                    {name}
                  </option>
                </select>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Order</span></label>
                <input
                  type="number"
                  name="environment[ordinal]"
                  value={@form[:ordinal].value || "0"}
                  min="0"
                  class="input input-bordered input-sm w-full"
                />
                <label class="label">
                  <span class="label-text-alt">Lower = earlier in promotion pipeline</span>
                </label>
              </div>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="environment[description]"
                value={@form[:description].value}
                maxlength="200"
                class="input input-bordered input-sm w-full"
                placeholder="Optional description"
              />
            </div>

            <div class="divider text-sm">Settings</div>

            <div class="flex flex-wrap gap-4">
              <div class="form-control">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="environment[approval_required]"
                    value="true"
                    checked={@form[:approval_required].value in [true, "true"]}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">Require approval for rollouts</span>
                </label>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Approvals Needed</span></label>
                <input
                  type="number"
                  name="environment[approvals_needed]"
                  value={@form[:approvals_needed].value || "1"}
                  min="1"
                  max="10"
                  class="input input-bordered input-sm w-24"
                />
              </div>
            </div>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                {if @editing_environment, do: "Update Environment", else: "Create Environment"}
              </button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={env <- @environments}
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span
                  class="w-3 h-3 rounded-full"
                  style={"background-color: #{env.color || "#6366f1"}"}
                >
                </span>
                <h3 class="card-title text-base">{env.name}</h3>
              </div>
              <span class="badge badge-sm badge-ghost">#{env.ordinal}</span>
            </div>

            <p :if={env.description} class="text-sm text-base-content/70 mt-1">
              {env.description}
            </p>

            <div class="flex flex-wrap gap-2 mt-2">
              <span class="badge badge-sm badge-info">
                {Map.get(@env_stats, env.id, 0)} nodes
              </span>
              <span
                :if={get_in(env.settings, ["approval_required"])}
                class="badge badge-sm badge-warning"
              >
                Approval required
              </span>
            </div>

            <div class="card-actions justify-end mt-3">
              <.link
                navigate={nodes_path(@org, @project, env)}
                class="btn btn-ghost btn-xs"
              >
                View Nodes
              </.link>
              <button phx-click="edit" phx-value-id={env.id} class="btn btn-ghost btn-xs">
                Edit
              </button>
              <button
                phx-click="delete"
                phx-value-id={env.id}
                data-confirm="Are you sure you want to delete this environment?"
                class="btn btn-ghost btn-xs text-error"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={@environments == []} class="text-center py-12 text-base-content/50">
        <p>No environments yet.</p>
        <p class="mt-2">
          <button class="btn btn-sm btn-primary" phx-click="create_defaults">
            Create default environments (dev, staging, prod)
          </button>
        </p>
      </div>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp nodes_path(%{slug: org_slug}, project, env),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/nodes?environment=#{env.slug}"

  defp nodes_path(nil, project, env),
    do: ~p"/projects/#{project.slug}/nodes?environment=#{env.slug}"

  defp build_environment_attrs(params, project_id) do
    settings = %{
      "approval_required" => params["approval_required"] in ["true", true],
      "approvals_needed" => parse_int(params["approvals_needed"], 1)
    }

    attrs = %{
      name: params["name"],
      description: params["description"],
      color: params["color"],
      ordinal: parse_int(params["ordinal"], 0),
      settings: settings
    }

    if project_id do
      Map.put(attrs, :project_id, project_id)
    else
      attrs
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
