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
  alias ZentinelCp.Auth.{OidcProvider, SamlProvider}
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
  Returns `{:ok, authorize_url, state, code_verifier}` or `{:error, reason}`.
  """
  def oidc_authorize_url(%OidcProvider{} = provider) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    code_verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

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
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      })

    authorize_url = derive_authorize_endpoint(provider.discovery_url)
    {:ok, "#{authorize_url}?#{params}", state, code_verifier}
  end

  @doc """
  Exchanges an OIDC authorization code for tokens and extracts user info.
  Returns `{:ok, user_info}` or `{:error, reason}`.
  """
  def oidc_callback(%OidcProvider{} = provider, code, code_verifier) do
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

    token_url = derive_token_endpoint(provider.discovery_url)

    with {:ok, token_response} <- exchange_token(token_url, token_params),
         {:ok, user_info} <- extract_user_info(token_response, provider) do
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

    encoded = Base.encode64(authn_request)

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
  def process_saml_response(saml_response, provider) do
    with {:ok, decoded} <- Base.decode64(saml_response),
         {:ok, assertion} <- parse_saml_assertion(decoded, provider) do
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

    user_attrs = %{
      email: user_info[:email],
      password: random_password,
      role: role
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

  defp derive_authorize_endpoint(discovery_url) do
    # In production, fetch from .well-known/openid-configuration
    # For now, derive common patterns
    uri = URI.parse(discovery_url)
    "#{uri.scheme}://#{uri.host}#{uri.path}/authorize"
  end

  defp derive_token_endpoint(discovery_url) do
    uri = URI.parse(discovery_url)
    "#{uri.scheme}://#{uri.host}#{uri.path}/token"
  end

  defp exchange_token(token_url, params) do
    case Req.post(token_url,
           form: Enum.map(params, fn {k, v} -> {to_string(k), v} end),
           headers: [{"content-type", "application/x-www-form-urlencoded"}]
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, {:token_exchange_error, reason}}
    end
  end

  defp extract_user_info(%{"id_token" => id_token}, _provider) do
    # Decode JWT without verification for user info extraction
    # (token was just received from the IdP via backchannel)
    case JOSE.JWT.peek_payload(id_token) do
      %JOSE.JWT{fields: fields} ->
        {:ok,
         %{
           sub: fields["sub"],
           email: fields["email"],
           name: fields["name"],
           groups: fields["groups"] || []
         }}

      _ ->
        {:error, :invalid_id_token}
    end
  end

  defp extract_user_info(_, _), do: {:error, :no_id_token}

  defp parse_saml_assertion(xml, _provider) do
    # Simplified SAML assertion parsing
    # In production, use samly for full XML signature verification
    with {:ok, name_id} <- extract_xml_value(xml, "NameID"),
         attributes <- extract_saml_attributes(xml) do
      {:ok, %{name_id: name_id, attributes: attributes}}
    end
  end

  defp extract_xml_value(xml, tag) do
    case Regex.run(~r/<(?:saml:)?#{tag}[^>]*>([^<]+)</, xml) do
      [_, value] -> {:ok, value}
      _ -> {:error, :missing_element}
    end
  end

  defp extract_saml_attributes(xml) do
    Regex.scan(
      ~r/<(?:saml:)?Attribute Name="([^"]+)"[^>]*>\s*<(?:saml:)?AttributeValue[^>]*>([^<]+)/,
      xml
    )
    |> Enum.reduce(%{}, fn [_, name, value], acc ->
      Map.update(acc, name, [value], &[value | &1])
    end)
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
