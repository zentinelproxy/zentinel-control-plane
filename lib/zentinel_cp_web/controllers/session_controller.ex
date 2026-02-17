defmodule ZentinelCpWeb.SessionController do
  use ZentinelCpWeb, :controller

  alias ZentinelCp.Accounts
  alias ZentinelCp.Audit
  alias ZentinelCpWeb.Plugs.Auth

  def create(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      Audit.log_user_action(user, "session.login", "user", user.id,
        metadata: %{ip: conn.remote_ip |> :inet.ntoa() |> to_string()}
      )

      Auth.log_in_user(conn, user)
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: "/login")
    end
  end

  def delete(conn, _params) do
    if user = conn.assigns[:current_user] do
      Audit.log_user_action(user, "session.logout", "user", user.id)
    end

    Auth.log_out_user(conn)
  end
end
