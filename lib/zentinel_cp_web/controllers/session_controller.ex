defmodule ZentinelCpWeb.SessionController do
  use ZentinelCpWeb, :controller

  alias ZentinelCp.Accounts
  alias ZentinelCp.Accounts.Totp
  alias ZentinelCp.Audit
  alias ZentinelCpWeb.Plugs.Auth

  def create(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      if Totp.mfa_enabled?(user.id) do
        conn
        |> configure_session(renew: true)
        |> put_session(:mfa_user_id, user.id)
        |> put_session(:mfa_started_at, System.system_time(:second))
        |> redirect(to: "/login/mfa")
      else
        complete_login(conn, user)
      end
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: "/login")
    end
  end

  @mfa_window_seconds 300

  def verify_mfa(conn, %{"code" => code}) do
    with user_id when is_binary(user_id) <- get_session(conn, :mfa_user_id),
         started_at when is_integer(started_at) <- get_session(conn, :mfa_started_at),
         true <- System.system_time(:second) - started_at <= @mfa_window_seconds,
         %{} = totp <- Totp.get_user_totp(user_id),
         {:ok, _totp} <- Totp.validate_totp(totp, code),
         %{} = user <- Accounts.get_user(user_id) do
      conn
      |> delete_session(:mfa_user_id)
      |> delete_session(:mfa_started_at)
      |> complete_login(user)
    else
      {:error, :invalid_code} ->
        conn
        |> put_flash(:error, "Invalid code")
        |> redirect(to: "/login/mfa")

      _ ->
        conn
        |> delete_session(:mfa_user_id)
        |> delete_session(:mfa_started_at)
        |> put_flash(:error, "Please sign in again")
        |> redirect(to: "/login")
    end
  end

  defp complete_login(conn, user) do
    Audit.log_user_action(user, "session.login", "user", user.id,
      metadata: %{ip: conn.remote_ip |> :inet.ntoa() |> to_string()}
    )

    Auth.log_in_user(conn, user)
  end

  def delete(conn, _params) do
    if user = conn.assigns[:current_user] do
      Audit.log_user_action(user, "session.logout", "user", user.id)
    end

    Auth.log_out_user(conn)
  end
end
