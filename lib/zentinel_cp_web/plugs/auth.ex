defmodule ZentinelCpWeb.Plugs.Auth do
  @moduledoc """
  Plug for authenticating operators via browser session.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias ZentinelCp.Accounts

  def init(opts), do: opts

  @doc """
  Fetches the current user from session token and assigns it.
  Does not halt — use `require_authenticated_user` for protection.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  @doc """
  Plug that requires an authenticated user.
  Redirects to login if not authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Plug that requires the current user to have one of the allowed roles.
  Redirects with flash on failure.

  ## Examples

      plug :require_role, ["admin"]
      plug :require_role, ["admin", "operator"]
  """
  def require_role(conn, allowed_roles) do
    user = conn.assigns[:current_user]

    if user && user.role in allowed_roles do
      conn
    else
      conn
      |> put_flash(:error, "You do not have permission to access this page.")
      |> redirect(to: "/projects")
      |> halt()
    end
  end

  @doc """
  Plug that redirects authenticated users away from auth pages.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/projects")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Logs in a user by creating a session token.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> redirect(to: "/projects")
  end

  @doc """
  Logs out a user by deleting the session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ZentinelCpWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: "/login")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      {nil, conn}
    end
  end
end
