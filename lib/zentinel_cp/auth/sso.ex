defmodule ZentinelCp.Auth.Sso do
  @moduledoc """
  SSO authentication context handling OIDC and SAML identity provider flows.

  Supports:
  - OIDC authorization code flow with PKCE
  - SAML 2.0 SP-initiated SSO
  - Just-In-Time (JIT) user provisioning
  - IdP group → org membership mapping
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Auth.{OidcProvider, SamlProvider, SamlValidator}
  alias ZentinelCp.Accounts.User
  alias ZentinelCp.Orgs

  require Logger

  ## OIDC Provider Management

  def list_oidc_providers(org_id) do
    from(p in OidcProvider, where: p.org_id == ^org_id, order_by: [asc: p.name])
    |> Repo.all()
  end

  def get_oidc_provider(id), do: Repo.get(OidcProvider, id)

  def get_oidc_provider!(id), do: Repo.get!(OidcProvider, id)

  def get_enabled_oidc_provider(org_id, issuer) do
    from(p in OidcProvider,
      where: p.org_id == ^org_id and p.issuer == ^issuer and p.enabled == true
    )
    |> Repo.one()
  end

  def create_oidc_provider(attrs) do
    %OidcProvider{}
    |> OidcProvider.changeset(attrs)
    |> Repo.insert()
  end

  def update_oidc_provider(%OidcProvider{} = provider, attrs) do
    provider
    |> OidcProvider.changeset(attrs)
    |> Repo.update()
  end

  def delete_oidc_provider(%OidcProvider{} = provider) do
    Repo.delete(provider)
  end

  ## SAML Provider Management

  def list_saml_providers(org_id) do
    from(p in SamlProvider, where: p.org_id == ^org_id, order_by: [asc: p.name])
    |> Repo.all()
  end

  def get_saml_provider(id), do: Repo.get(SamlProvider, id)

  def get_saml_provider!(id), do: Repo.get!(SamlProvider, id)

  def get_enabled_saml_provider(org_id, entity_id) do
    from(p in SamlProvider,
      where: p.org_id == ^org_id and p.entity_id == ^entity_id and p.enabled == true
    )
    |> Repo.one()
  end

  def create_saml_provider(attrs) do
    %SamlProvider{}
    |> SamlProvider.changeset(attrs)
    |> Repo.insert()
  end

  def update_saml_provider(%SamlProvider{} = provider, attrs) do
    provider
    |> SamlProvider.changeset(attrs)
    |> Repo.update()
  end

  def delete_saml_provider(%SamlProvider{} = provider) do
    Repo.delete(provider)
  end

  ## OIDC Flow

  @doc """
  Generates the OIDC authorization URL with PKCE challenge.
  Returns `{:ok, authorize_url, state, code_verifier, nonce}` or `{:error, reason}`.
  """
  def oidc_authorize_url(%OidcProvider{} = provider) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    code_verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    code_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    # Decrypt now to validate configuration; secret used in token exchange step
    _client_secret = OidcProvider.decrypt_client_secret(provider)

    redirect_uri = oidc_callback_url()

    params =
      URI.encode_query(%{
        response_type: "code",
        client_id: provider.client_id,
        redirect_uri: redirect_uri,
        scope: Enum.join(provider.scopes, " "),
        state: state,
        nonce: nonce,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      })

    with {:ok, discovery} <- fetch_discovery(provider) do
      {:ok, "#{discovery["authorization_endpoint"]}?#{params}", state, code_verifier, nonce}
    end
  end

  @doc """
  Exchanges an OIDC authorization code for tokens and extracts user info.
  Returns `{:ok, user_info}` or `{:error, reason}`.
  """
  def oidc_callback(%OidcProvider{} = provider, code, code_verifier, nonce \\ nil) do
    client_secret = OidcProvider.decrypt_client_secret(provider)
    redirect_uri = oidc_callback_url()

    token_params = %{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: provider.client_id,
      client_secret: client_secret,
      code_verifier: code_verifier
    }

    with {:ok, discovery} <- fetch_discovery(provider),
         {:ok, token_response} <- exchange_token(discovery["token_endpoint"], token_params),
         {:ok, user_info} <- extract_user_info(token_response, provider, discovery, nonce) do
      {:ok, user_info}
    end
  end

  @doc """
  Processes an SSO login — finds or provisions the user and creates org membership.
  Returns `{:ok, user}` or `{:error, reason}`.
  """
  def process_sso_login(provider_type, provider, user_info) do
    provider_id = provider.id
    subject = user_info[:sub] || user_info[:email]

    case find_sso_user(provider_type, provider_id, subject) do
      %User{} = user ->
        {:ok, user}

      nil ->
        if provider.auto_provision do
          provision_sso_user(provider_type, provider, user_info)
        else
          {:error, :user_not_provisioned}
        end
    end
  end

  ## SAML Flow

  @doc """
  Generates a SAML authn request URL for SP-initiated SSO.
  Returns `{:ok, url, request_id}` or `{:error, reason}`.
  """
  def saml_authn_request_url(%SamlProvider{} = provider) do
    request_id = "_#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    sp_entity_id = saml_sp_entity_id()
    acs_url = saml_acs_url()

    authn_request = """
    <samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
      xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
      ID="#{request_id}"
      Version="2.0"
      IssueInstant="#{now}"
      Destination="#{provider.sso_url}"
      AssertionConsumerServiceURL="#{acs_url}">
      <saml:Issuer>#{sp_entity_id}</saml:Issuer>
      <samlp:NameIDPolicy Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
        AllowCreate="true"/>
    </samlp:AuthnRequest>
    """

    # The HTTP-Redirect binding requires raw DEFLATE before Base64.
    encoded = authn_request |> :zlib.zip() |> Base.encode64()

    params =
      URI.encode_query(%{
        SAMLRequest: encoded,
        RelayState: provider.org_id
      })

    {:ok, "#{provider.sso_url}?#{params}", request_id}
  end

  @doc """
  Processes a SAML assertion response.
  Returns `{:ok, user_info}` or `{:error, reason}`.
  """
  def process_saml_response(saml_response, provider, opts \\ []) do
    validation = [
      audience: saml_sp_entity_id(),
      recipient: saml_acs_url(),
      request_id: opts[:request_id]
    ]

    with {:ok, decoded} <- decode_saml_response(saml_response),
         {:ok, assertion} <- SamlValidator.validate(decoded, provider, validation) do
      user_info = %{
        email: assertion[:name_id],
        sub: assertion[:name_id],
        name: assertion[:attributes]["displayName"],
        groups: assertion[:attributes]["groups"] || []
      }

      {:ok, user_info}
    end
  end

  ## Private Helpers

  defp find_sso_user(provider_type, provider_id, subject) do
    from(u in User,
      where:
        u.sso_provider_type == ^to_string(provider_type) and
          u.sso_provider_id == ^provider_id and
          u.sso_subject == ^subject
    )
    |> Repo.one()
  end

  defp provision_sso_user(provider_type, provider, user_info) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    role = resolve_role(provider, user_info[:groups] || [])
    random_password = Base.url_encode64(:crypto.strong_rand_bytes(32))

    # `role` applies to this org only. A global admin can reach every org, so an
    # identity provider must not be able to grant it.
    user_attrs = %{
      email: user_info[:email],
      password: random_password,
      role: "reader"
    }

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, fn _ ->
      %User{}
      |> User.registration_changeset(user_attrs)
      |> Ecto.Changeset.put_change(:sso_provider_type, to_string(provider_type))
      |> Ecto.Changeset.put_change(:sso_provider_id, provider.id)
      |> Ecto.Changeset.put_change(:sso_subject, user_info[:sub] || user_info[:email])
      |> Ecto.Changeset.put_change(:sso_provisioned_at, now)
      |> Ecto.Changeset.put_change(:confirmed_at, now)
    end)
    |> Ecto.Multi.run(:membership, fn _repo, %{user: user} ->
      org = Orgs.get_org!(provider.org_id)
      Orgs.add_member(org, user, role)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :membership, reason, _} -> {:error, reason}
    end
  end

  defp resolve_role(provider, groups) do
    case provider.group_mapping do
      mapping when map_size(mapping) > 0 ->
        Enum.find_value(groups, provider.default_role, fn group ->
          Map.get(mapping, group)
        end)

      _ ->
        provider.default_role
    end
  end

  defp fetch_discovery(%OidcProvider{} = provider) do
    case http_get(provider.discovery_url) do
      {:ok, %{"issuer" => issuer} = discovery} when issuer == provider.issuer ->
        {:ok, discovery}

      {:ok, %{"issuer" => _}} ->
        {:error, :issuer_mismatch}

      {:ok, _} ->
        {:error, :invalid_discovery_document}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(url) do
    case Req.get(url, oidc_req_options()) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp oidc_req_options, do: Application.get_env(:zentinel_cp, :oidc_req_options, [])

  defp exchange_token(token_url, params) do
    options =
      [form: Enum.map(params, fn {k, v} -> {to_string(k), v} end)] ++ oidc_req_options()

    case Req.post(token_url, options) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, {:token_exchange_error, reason}}
    end
  end

  defp extract_user_info(%{"id_token" => id_token}, provider, discovery, nonce) do
    with {:ok, jwks} <- http_get(discovery["jwks_uri"]),
         {:ok, fields} <- verify_id_token(id_token, jwks),
         :ok <- validate_id_token_claims(fields, provider, nonce) do
      {:ok,
       %{
         sub: fields["sub"],
         email: fields["email"],
         name: fields["name"],
         groups: fields["groups"] || []
       }}
    end
  end

  defp extract_user_info(_, _, _, _), do: {:error, :no_id_token}

  # Only asymmetric algorithms: the key comes from the provider's JWKS, so
  # accepting HS* or "none" would let a forged token choose how it is checked.
  @id_token_algorithms ["RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "PS256", "EdDSA"]

  defp verify_id_token(id_token, %{"keys" => keys}) when is_list(keys) do
    kid = id_token_kid(id_token)

    verified =
      keys
      |> Enum.filter(&(is_nil(kid) or &1["kid"] == kid))
      |> Enum.find_value(fn key ->
        case JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), @id_token_algorithms, id_token) do
          {true, %JOSE.JWT{fields: fields}, _jws} -> fields
          _ -> nil
        end
      end)

    if verified, do: {:ok, verified}, else: {:error, :invalid_id_token}
  rescue
    _ -> {:error, :invalid_id_token}
  end

  defp verify_id_token(_, _), do: {:error, :invalid_jwks}

  defp id_token_kid(id_token) do
    case JOSE.JWT.peek_protected(id_token) do
      %JOSE.JWS{fields: %{"kid" => kid}} -> kid
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp validate_id_token_claims(fields, provider, nonce) do
    now = System.system_time(:second)

    cond do
      fields["iss"] != provider.issuer -> {:error, :invalid_issuer}
      provider.client_id not in List.wrap(fields["aud"]) -> {:error, :invalid_audience}
      not is_integer(fields["exp"]) or fields["exp"] <= now -> {:error, :token_expired}
      is_nil(nonce) or fields["nonce"] != nonce -> {:error, :invalid_nonce}
      true -> :ok
    end
  end

  defp decode_saml_response(saml_response) do
    case Base.decode64(saml_response, ignore: :whitespace) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_encoding}
    end
  end

  defp oidc_callback_url do
    ZentinelCpWeb.Endpoint.url() <> "/auth/oidc/callback"
  end

  defp saml_acs_url do
    ZentinelCpWeb.Endpoint.url() <> "/auth/saml/acs"
  end

  defp saml_sp_entity_id do
    ZentinelCpWeb.Endpoint.url()
  end

  ## Provider lookup for login page

  @doc """
  Lists all enabled SSO providers for an org (both OIDC and SAML).
  Returns a list of `{type, id, name}` tuples.
  """
  def list_sso_providers_for_org(org_id) do
    oidc =
      from(p in OidcProvider,
        where: p.org_id == ^org_id and p.enabled == true,
        select: {type(^"oidc", :string), p.id, p.name}
      )
      |> Repo.all()

    saml =
      from(p in SamlProvider,
        where: p.org_id == ^org_id and p.enabled == true,
        select: {type(^"saml", :string), p.id, p.name}
      )
      |> Repo.all()

    oidc ++ saml
  end

  @doc """
  Checks if any org has password fallback disabled, which means
  SSO is the only login method.
  """
  def password_login_allowed_for_user?(%User{sso_provider_type: nil}), do: true

  def password_login_allowed_for_user?(%User{sso_provider_type: "oidc"} = user) do
    case Repo.get(OidcProvider, user.sso_provider_id) do
      %OidcProvider{fallback_to_password: true} -> true
      _ -> false
    end
  end

  def password_login_allowed_for_user?(%User{sso_provider_type: "saml"} = user) do
    case Repo.get(SamlProvider, user.sso_provider_id) do
      %SamlProvider{fallback_to_password: true} -> true
      _ -> false
    end
  end
end
