defmodule ZentinelCpWeb.AuthLive.Mfa do
  @moduledoc """
  Second login step for users with MFA enabled. Accepts a TOTP or recovery code.
  """
  use ZentinelCpWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="w-full max-w-sm p-8">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold">Two-factor authentication</h1>
          <p class="text-base-content/60 mt-2">Enter a code from your authenticator app</p>
        </div>

        <.form for={@form} action={~p"/session/mfa"} method="post" class="space-y-4">
          <div class="form-control">
            <label class="label" for="code">
              <span class="label-text">Authentication or recovery code</span>
            </label>
            <input
              type="text"
              name="code"
              id="code"
              autocomplete="one-time-code"
              required
              autofocus
              class="input input-bordered w-full"
            />
          </div>
          <button type="submit" class="btn btn-primary w-full">Verify</button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    if session["mfa_user_id"] do
      {:ok, assign(socket, page_title: "Two-factor authentication", form: to_form(%{}))}
    else
      {:ok, redirect(socket, to: "/login")}
    end
  end
end
