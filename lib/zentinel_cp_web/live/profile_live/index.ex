defmodule ZentinelCpWeb.ProfileLive.Index do
  @moduledoc """
  LiveView for user profile management - password change and preferences.
  """
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Accounts, Audit}
  alias ZentinelCp.Accounts.{Totp, UserTotp}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Profile",
       show_password_form: false,
       password_form: to_form(%{}, as: "password"),
       mfa_enabled: Totp.mfa_enabled?(socket.assigns.current_user.id),
       mfa_enrollment: nil,
       recovery_codes: nil
     )}
  end

  @impl true
  def handle_event("start_mfa", _, socket) do
    user = socket.assigns.current_user

    case Totp.get_user_totp(user.id) do
      %UserTotp{verified_at: %DateTime{}} ->
        {:noreply, socket}

      _ ->
        {:ok, totp} = Totp.create_user_totp(user.id)

        {:noreply,
         assign(socket,
           mfa_enrollment: %{
             uri: UserTotp.otpauth_uri(totp, user.email),
             secret: Base.encode32(totp.secret, padding: false)
           },
           recovery_codes: totp.plain_recovery_codes
         )}
    end
  end

  def handle_event("confirm_mfa", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    with %UserTotp{} = totp <- Totp.get_user_totp(user.id),
         {:ok, _totp} <- Totp.verify_totp_enrollment(totp, code) do
      Audit.log_user_action(user, "mfa.enabled", "user", user.id)

      {:noreply,
       socket
       |> assign(mfa_enabled: true, mfa_enrollment: nil, recovery_codes: nil)
       |> put_flash(:info, "Two-factor authentication enabled.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid code. Please try again.")}
    end
  end

  def handle_event("disable_mfa", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    with %UserTotp{} = totp <- Totp.get_user_totp(user.id),
         {:ok, totp} <- Totp.validate_totp(totp, code),
         {:ok, _} <- Totp.delete_user_totp(totp) do
      Audit.log_user_action(user, "mfa.disabled", "user", user.id)

      {:noreply,
       socket
       |> assign(mfa_enabled: false)
       |> put_flash(:info, "Two-factor authentication disabled.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid code.")}
    end
  end

  @impl true
  def handle_event("toggle_password_form", _, socket) do
    {:noreply,
     assign(socket,
       show_password_form: !socket.assigns.show_password_form,
       password_form: to_form(%{}, as: "password")
     )}
  end

  @impl true
  def handle_event("change_password", %{"password" => params}, socket) do
    current_user = socket.assigns.current_user

    case Accounts.update_user_password(current_user, params["current_password"], %{
           password: params["new_password"],
           password_confirmation: params["new_password_confirmation"]
         }) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(show_password_form: false, password_form: to_form(%{}, as: "password"))
         |> put_flash(:info, "Password updated successfully.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(password_form: to_form(changeset, as: "password"))
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-xl font-bold">Profile</h1>

      <.k8s_section title="Two-factor authentication">
        <div :if={@mfa_enabled} class="space-y-3">
          <p class="text-sm">Two-factor authentication is on.</p>
          <form phx-submit="disable_mfa" class="flex gap-2">
            <input
              type="text"
              name="code"
              required
              placeholder="Current code"
              autocomplete="one-time-code"
              class="input input-bordered input-sm"
            />
            <button type="submit" class="btn btn-sm btn-error">Disable</button>
          </form>
        </div>
        <div :if={!@mfa_enabled && !@mfa_enrollment} class="space-y-3">
          <p class="text-sm">Protect your account with an authenticator app.</p>
          <button type="button" phx-click="start_mfa" class="btn btn-sm btn-primary">
            Set up
          </button>
        </div>
        <div :if={@mfa_enrollment} class="space-y-3">
          <p class="text-sm">
            Add this key to your authenticator app, or open the link on your phone.
          </p>
          <p class="font-mono text-sm break-all" id="mfa-secret">{@mfa_enrollment.secret}</p>
          <p class="font-mono text-xs break-all">{@mfa_enrollment.uri}</p>
          <p class="text-sm font-medium">
            Save these recovery codes now. Each works once, and they won't be shown again.
          </p>
          <ul class="font-mono text-sm" id="mfa-recovery-codes">
            <li :for={code <- @recovery_codes}>{code}</li>
          </ul>
          <form phx-submit="confirm_mfa" class="flex gap-2">
            <input
              type="text"
              name="code"
              required
              placeholder="Code from your app"
              autocomplete="one-time-code"
              class="input input-bordered input-sm"
            />
            <button type="submit" class="btn btn-sm btn-primary">Confirm</button>
          </form>
        </div>
      </.k8s_section>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.k8s_section title="Account Information">
          <.definition_list>
            <:item label="Email">
              <span class="font-mono">{@current_user.email}</span>
            </:item>
            <:item label="Role">
              <span class={"badge badge-sm #{role_badge_class(@current_user.role)}"}>
                {@current_user.role}
              </span>
            </:item>
            <:item label="Member Since">
              {Calendar.strftime(@current_user.inserted_at, "%Y-%m-%d")}
            </:item>
            <:item label="User ID">
              <span class="font-mono text-xs">{@current_user.id}</span>
            </:item>
          </.definition_list>
        </.k8s_section>

        <.k8s_section title="Security">
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <div>
                <div class="font-medium">Password</div>
                <div class="text-sm text-base-content/50">
                  Change your account password
                </div>
              </div>
              <button
                class="btn btn-outline btn-sm"
                phx-click="toggle_password_form"
              >
                {if @show_password_form, do: "Cancel", else: "Change Password"}
              </button>
            </div>

            <div :if={@show_password_form} class="border-t border-base-300 pt-4">
              <form phx-submit="change_password" class="space-y-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Current Password</span>
                  </label>
                  <input
                    type="password"
                    name="password[current_password]"
                    required
                    class="input input-bordered input-sm w-full"
                    autocomplete="current-password"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">New Password</span>
                  </label>
                  <input
                    type="password"
                    name="password[new_password]"
                    required
                    minlength="12"
                    class="input input-bordered input-sm w-full"
                    autocomplete="new-password"
                  />
                  <label class="label">
                    <span class="label-text-alt text-base-content/50">
                      Minimum 12 characters
                    </span>
                  </label>
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Confirm New Password</span>
                  </label>
                  <input
                    type="password"
                    name="password[new_password_confirmation]"
                    required
                    class="input input-bordered input-sm w-full"
                    autocomplete="new-password"
                  />
                </div>
                <button type="submit" class="btn btn-primary btn-sm">
                  Update Password
                </button>
              </form>
            </div>
          </div>
        </.k8s_section>
      </div>

      <.k8s_section title="Sessions">
        <div class="text-sm text-base-content/50">
          <p>You are currently logged in.</p>
          <p class="mt-2">
            <.link href={~p"/session"} method="delete" class="link link-error">
              Log out of this session
            </.link>
          </p>
        </div>
      </.k8s_section>
    </div>
    """
  end

  defp role_badge_class("admin"), do: "badge-error"
  defp role_badge_class("operator"), do: "badge-warning"
  defp role_badge_class("reader"), do: "badge-info"
  defp role_badge_class(_), do: "badge-ghost"

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
