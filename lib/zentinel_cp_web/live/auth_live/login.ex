defmodule ZentinelCpWeb.AuthLive.Login do
  use ZentinelCpWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-[60vh]">
      <div class="w-full max-w-sm">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold">Sign in</h1>
          <p class="text-base-content/60 mt-2">Zentinel Control Plane</p>
        </div>

        <.form
          for={@form}
          action={~p"/session"}
          method="post"
          class="space-y-4"
        >
          <div class="form-control">
            <label class="label" for="email">
              <span class="label-text">Email</span>
            </label>
            <input
              type="email"
              name="email"
              id="email"
              value={@form[:email].value}
              required
              autofocus
              class="input input-bordered w-full"
              placeholder="you@example.com"
            />
          </div>

          <div class="form-control">
            <label class="label" for="password">
              <span class="label-text">Password</span>
            </label>
            <input
              type="password"
              name="password"
              id="password"
              required
              class="input input-bordered w-full"
              placeholder="••••••••••••"
            />
          </div>

          <button type="submit" class="btn btn-primary w-full">
            Sign in
          </button>
        </.form>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: :user)
    {:ok, assign(socket, form: form, page_title: "Sign in")}
  end
end
