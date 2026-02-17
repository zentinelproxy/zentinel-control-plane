defmodule ZentinelCpWeb.OrgsLive.Show do
  @moduledoc """
  LiveView for showing org details and managing members.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Accounts, Audit, Orgs}

  @impl true
  def mount(%{"org_slug" => slug}, _session, socket) do
    case Orgs.get_org_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      org ->
        members = Orgs.list_members(org)
        user_role = Orgs.get_user_role(org.id, socket.assigns.current_user.id)

        {:ok,
         assign(socket,
           page_title: org.name,
           org: org,
           members: members,
           user_role: user_role,
           show_edit: false,
           show_add_member: false
         )}
    end
  end

  @impl true
  def handle_event("toggle_edit", _, socket) do
    {:noreply, assign(socket, show_edit: !socket.assigns.show_edit)}
  end

  def handle_event("update_org", %{"name" => name}, socket) do
    org = socket.assigns.org

    case Orgs.update_org(org, %{name: name}) do
      {:ok, updated_org} ->
        Audit.log_user_action(socket.assigns.current_user, "update", "org", updated_org.id,
          org_id: updated_org.id
        )

        {:noreply,
         socket
         |> assign(org: updated_org, show_edit: false, page_title: updated_org.name)
         |> put_flash(:info, "Organization updated.")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Could not update organization: #{errors}")}
    end
  end

  def handle_event("toggle_add_member", _, socket) do
    {:noreply, assign(socket, show_add_member: !socket.assigns.show_add_member)}
  end

  def handle_event("add_member", %{"email" => email, "role" => role}, socket) do
    org = socket.assigns.org

    case Accounts.get_user_by_email(email) do
      nil ->
        {:noreply, put_flash(socket, :error, "No user found with email #{email}")}

      user ->
        case Orgs.add_member(org, user, role) do
          {:ok, _membership} ->
            Audit.log_user_action(socket.assigns.current_user, "add_member", "org", org.id,
              org_id: org.id
            )

            members = Orgs.list_members(org)

            {:noreply,
             socket
             |> assign(members: members, show_add_member: false)
             |> put_flash(:info, "Member added.")}

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

            {:noreply, put_flash(socket, :error, "Could not add member: #{errors}")}
        end
    end
  end

  def handle_event("update_role", %{"membership_id" => membership_id, "role" => role}, socket) do
    org = socket.assigns.org
    membership = Enum.find(socket.assigns.members, &(&1.id == membership_id))

    case Orgs.update_member_role(membership, role) do
      {:ok, _} ->
        Audit.log_user_action(socket.assigns.current_user, "update_role", "org", org.id,
          org_id: org.id
        )

        members = Orgs.list_members(org)
        {:noreply, socket |> assign(members: members) |> put_flash(:info, "Role updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_event("remove_member", %{"id" => membership_id}, socket) do
    org = socket.assigns.org
    membership = Enum.find(socket.assigns.members, &(&1.id == membership_id))

    if membership.user_id == socket.assigns.current_user.id do
      {:noreply, put_flash(socket, :error, "You cannot remove yourself.")}
    else
      case Orgs.remove_member(org, membership.user) do
        {_count, _} ->
          Audit.log_user_action(socket.assigns.current_user, "remove_member", "org", org.id,
            org_id: org.id
          )

          members = Orgs.list_members(org)
          {:noreply, socket |> assign(members: members) |> put_flash(:info, "Member removed.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header name={@org.name} resource_type="org" back_path={~p"/orgs"}>
        <:badge><span class="badge badge-ghost font-mono">{@org.slug}</span></:badge>
        <:action>
          <button class="btn btn-ghost btn-sm" phx-click="toggle_edit">Edit</button>
        </:action>
      </.detail_header>

      <div :if={@show_edit}>
        <.k8s_section title="Edit Organization">
          <form phx-submit="update_org" class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="name"
                required
                value={@org.name}
                class="input input-bordered input-sm w-full max-w-xs"
              />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="toggle_edit">
                Cancel
              </button>
            </div>
          </form>
        </.k8s_section>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Quick Links">
          <div class="flex flex-col gap-2">
            <.link navigate={~p"/orgs/#{@org.slug}/projects"} class="link link-primary text-sm">
              Projects
            </.link>
            <.link navigate={~p"/orgs/#{@org.slug}/dashboard"} class="link link-primary text-sm">
              Dashboard
            </.link>
          </div>
        </.k8s_section>

        <.k8s_section title="Members">
          <.table_toolbar>
            <:actions>
              <button class="btn btn-primary btn-xs" phx-click="toggle_add_member">
                Add Member
              </button>
            </:actions>
          </.table_toolbar>

          <div :if={@show_add_member} class="bg-base-300 rounded p-4 mb-3">
            <form phx-submit="add_member" class="space-y-3">
              <div class="form-control">
                <label class="label"><span class="label-text">Email</span></label>
                <input
                  type="email"
                  name="email"
                  required
                  class="input input-bordered input-sm w-full"
                  placeholder="user@example.com"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Role</span></label>
                <select name="role" class="select select-bordered select-sm w-full">
                  <option value="reader">Reader</option>
                  <option value="operator">Operator</option>
                  <option value="admin">Admin</option>
                </select>
              </div>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-xs">Add</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="toggle_add_member">
                  Cancel
                </button>
              </div>
            </form>
          </div>

          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Email</th>
                <th class="text-xs uppercase">Role</th>
                <th class="text-xs uppercase"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={membership <- @members}>
                <td class="text-sm">{membership.user.email}</td>
                <td>
                  <%= if membership.user_id == @current_user.id do %>
                    <span class={[
                      "badge badge-sm",
                      membership.role == "admin" && "badge-primary",
                      membership.role == "operator" && "badge-warning",
                      membership.role == "reader" && "badge-ghost"
                    ]}>
                      {membership.role}
                    </span>
                  <% else %>
                    <form phx-change="update_role" class="inline">
                      <input type="hidden" name="membership_id" value={membership.id} />
                      <select
                        name="role"
                        class="select select-bordered select-xs"
                        onchange="this.form.dispatchEvent(new Event('change', {bubbles: true}))"
                      >
                        <option value="reader" selected={membership.role == "reader"}>reader</option>
                        <option value="operator" selected={membership.role == "operator"}>
                          operator
                        </option>
                        <option value="admin" selected={membership.role == "admin"}>admin</option>
                      </select>
                    </form>
                  <% end %>
                </td>
                <td>
                  <%= if membership.user_id != @current_user.id do %>
                    <button
                      phx-click="remove_member"
                      phx-value-id={membership.id}
                      data-confirm="Remove this member from the organization?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Remove
                    </button>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </.k8s_section>
      </div>
    </div>
    """
  end
end
