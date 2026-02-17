defmodule ZentinelCpWeb.Auth.SsoController do
  use ZentinelCpWeb, :controller

  alias ZentinelCp.Auth.Sso
  alias ZentinelCp.Audit
  alias ZentinelCpWeb.Plugs.Auth

  @doc """
  Initiates OIDC login by redirecting to the IdP authorization endpoint.
  """
  def oidc_login(conn, %{"provider_id" => provider_id}) do
    case Sso.get_oidc_provider(provider_id) do
      nil ->
        conn
        |> put_flash(:error, "SSO provider not found")
        |> redirect(to: "/login")

      provider ->
        case Sso.oidc_authorize_url(provider) do
          {:ok, url, state, code_verifier} ->
            conn
            |> put_session(:oidc_state, state)
            |> put_session(:oidc_code_verifier, code_verifier)
            |> put_session(:oidc_provider_id, provider_id)
            |> redirect(external: url)

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Failed to initiate SSO login")
            |> redirect(to: "/login")
        end
    end
  end

  @doc """
  Handles the OIDC callback from the IdP after authorization.
  """
  def oidc_callback(conn, %{"code" => code, "state" => state}) do
    saved_state = get_session(conn, :oidc_state)
    code_verifier = get_session(conn, :oidc_code_verifier)
    provider_id = get_session(conn, :oidc_provider_id)

    conn =
      conn
      |> delete_session(:oidc_state)
      |> delete_session(:oidc_code_verifier)
      |> delete_session(:oidc_provider_id)

    with true <- Plug.Crypto.secure_compare(state, saved_state || ""),
         provider when not is_nil(provider) <- Sso.get_oidc_provider(provider_id),
         {:ok, user_info} <- Sso.oidc_callback(provider, code, code_verifier),
         {:ok, user} <- Sso.process_sso_login(:oidc, provider, user_info) do
      Audit.log_user_action(user, "session.sso_login", "user", user.id,
        metadata: %{
          provider_type: "oidc",
          provider_id: provider_id,
          ip: conn.remote_ip |> :inet.ntoa() |> to_string()
        }
      )

      Auth.log_in_user(conn, user)
    else
      false ->
        conn
        |> put_flash(:error, "SSO state mismatch — possible CSRF attack")
        |> redirect(to: "/login")

      {:error, :user_not_provisioned} ->
        conn
        |> put_flash(:error, "Your account has not been provisioned. Contact your administrator.")
        |> redirect(to: "/login")

      _ ->
        conn
        |> put_flash(:error, "SSO authentication failed")
        |> redirect(to: "/login")
    end
  end

  def oidc_callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "SSO login denied: #{error}")
    |> redirect(to: "/login")
  end

  @doc """
  Initiates SAML SP-initiated login by redirecting to the IdP.
  """
  def saml_login(conn, %{"provider_id" => provider_id}) do
    case Sso.get_saml_provider(provider_id) do
      nil ->
        conn
        |> put_flash(:error, "SSO provider not found")
        |> redirect(to: "/login")

      provider ->
        case Sso.saml_authn_request_url(provider) do
          {:ok, url, request_id} ->
            conn
            |> put_session(:saml_request_id, request_id)
            |> put_session(:saml_provider_id, provider_id)
            |> redirect(external: url)

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Failed to initiate SAML login")
            |> redirect(to: "/login")
        end
    end
  end

  @doc """
  Handles the SAML ACS (Assertion Consumer Service) callback.
  """
  def saml_acs(conn, %{"SAMLResponse" => saml_response}) do
    provider_id = get_session(conn, :saml_provider_id)

    conn =
      conn
      |> delete_session(:saml_request_id)
      |> delete_session(:saml_provider_id)

    with provider when not is_nil(provider) <- Sso.get_saml_provider(provider_id),
         {:ok, user_info} <- Sso.process_saml_response(saml_response, provider),
         {:ok, user} <- Sso.process_sso_login(:saml, provider, user_info) do
      Audit.log_user_action(user, "session.sso_login", "user", user.id,
        metadata: %{
          provider_type: "saml",
          provider_id: provider_id,
          ip: conn.remote_ip |> :inet.ntoa() |> to_string()
        }
      )

      Auth.log_in_user(conn, user)
    else
      {:error, :user_not_provisioned} ->
        conn
        |> put_flash(:error, "Your account has not been provisioned. Contact your administrator.")
        |> redirect(to: "/login")

      _ ->
        conn
        |> put_flash(:error, "SAML authentication failed")
        |> redirect(to: "/login")
    end
  end

  def saml_acs(conn, _params) do
    conn
    |> put_flash(:error, "Invalid SAML response")
    |> redirect(to: "/login")
  end
end
