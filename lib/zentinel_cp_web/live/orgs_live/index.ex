defmodule ZentinelCpWeb.OrgsLive.Index do
  @moduledoc """
  LiveView for listing organizations the current user belongs to.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_memberships = Orgs.list_user_orgs(user.id)

    {:ok,
     socket
     |> assign(:org_memberships, org_memberships)
     |> assign(:show_form, false)
     |> assign(:page_title, "Organizations")}
  end

  @impl true
  def handle_event("toggle_form", _, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  def handle_event("create_org", %{"name" => name}, socket) do
    user = socket.assigns.current_user

    case Orgs.create_org_with_owner(%{name: name}, user) do
      {:ok, org} ->
        Audit.log_user_action(user, "create", "org", org.id, org_id: org.id)
        org_memberships = Orgs.list_user_orgs(user.id)

        {:noreply,
         socket
         |> assign(org_memberships: org_memberships, show_form: false)
         |> put_flash(:info, "Organization created.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Could not create organization: #{errors}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-xl font-bold">Organizations</h1>
        <button class="btn btn-primary btn-sm" phx-click="toggle_form">
          New Organization
        </button>
      </div>

      <div :if={@show_form}>
        <.k8s_section title="Create Organization">
          <form phx-submit="create_org" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="e.g. My Organization"
              />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Create</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_form">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for {org, role} <- @org_memberships do %>
          <.link
            navigate={~p"/orgs/#{org.slug}/projects"}
            class="bg-base-200 rounded border border-base-300 p-6 hover:border-primary/50 transition-colors"
          >
            <div class="flex items-center gap-2">
              <.resource_badge type="org" />
              <h2 class="text-lg font-semibold">{org.name}</h2>
              <span class="badge badge-sm badge-ghost">{role}</span>
            </div>
            <div class="mt-4 text-sm text-base-content/50">
              <span class="font-mono">{org.slug}</span>
            </div>
          </.link>
        <% end %>
      </div>

      <%= if Enum.empty?(@org_memberships) do %>
        <.k8s_section>
          <div class="text-center text-base-content/50 py-4">
            <p>You are not a member of any organizations.</p>
          </div>
        </.k8s_section>
      <% end %>
    </div>
    """
  end
end
