defmodule ZentinelCp.Auth.SsoTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Auth.Sso
  alias ZentinelCp.Auth.OidcProvider

  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OrgsFixtures

  setup do
    org = org_fixture()
    %{org: org}
  end

  describe "OIDC provider management" do
    test "creates an OIDC provider", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "Okta",
        issuer: "https://dev-123.okta.com",
        client_id: "test-client-id",
        client_secret: "test-client-secret",
        discovery_url: "https://dev-123.okta.com/.well-known/openid-configuration"
      }

      assert {:ok, provider} = Sso.create_oidc_provider(attrs)
      assert provider.name == "Okta"
      assert provider.issuer == "https://dev-123.okta.com"
      assert provider.client_id == "test-client-id"
      assert provider.auto_provision == true
      assert provider.default_role == "reader"
      assert provider.enabled == true
    end

    test "encrypts client secret on create", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "Azure AD",
        issuer: "https://login.microsoftonline.com/tenant",
        client_id: "azure-client",
        client_secret: "super-secret-value",
        discovery_url:
          "https://login.microsoftonline.com/tenant/v2.0/.well-known/openid-configuration"
      }

      assert {:ok, provider} = Sso.create_oidc_provider(attrs)
      assert provider.client_secret_encrypted != nil
      assert provider.client_secret_encrypted != "super-secret-value"
      assert OidcProvider.decrypt_client_secret(provider) == "super-secret-value"
    end

    test "requires client_secret on create", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "NoSecret",
        issuer: "https://example.com",
        client_id: "client",
        discovery_url: "https://example.com/.well-known/openid-configuration"
      }

      assert {:error, changeset} = Sso.create_oidc_provider(attrs)
      assert "can't be blank" in errors_on(changeset).client_secret
    end

    test "lists providers for an org", %{org: org} do
      other_org = org_fixture()

      {:ok, _} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration"
        })

      {:ok, _} =
        Sso.create_oidc_provider(%{
          org_id: other_org.id,
          name: "Other",
          issuer: "https://other.example.com",
          client_id: "c2",
          client_secret: "s2",
          discovery_url: "https://other.example.com/.well-known/openid-configuration"
        })

      providers = Sso.list_oidc_providers(org.id)
      assert length(providers) == 1
      assert hd(providers).name == "Okta"
    end

    test "enforces unique issuer per org", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "Okta",
        issuer: "https://dev-123.okta.com",
        client_id: "c1",
        client_secret: "s1",
        discovery_url: "https://dev-123.okta.com/.well-known/openid-configuration"
      }

      assert {:ok, _} = Sso.create_oidc_provider(attrs)

      assert {:error, changeset} =
               Sso.create_oidc_provider(%{attrs | name: "Okta 2", client_id: "c2"})

      assert "has already been taken" in errors_on(changeset).org_id
    end

    test "updates an OIDC provider", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration"
        })

      assert {:ok, updated} = Sso.update_oidc_provider(provider, %{name: "Okta Production"})
      assert updated.name == "Okta Production"
    end

    test "deletes an OIDC provider", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration"
        })

      assert {:ok, _} = Sso.delete_oidc_provider(provider)
      assert Sso.get_oidc_provider(provider.id) == nil
    end
  end

  describe "SAML provider management" do
    test "creates a SAML provider", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "ADFS",
        entity_id: "https://adfs.example.com/adfs/services/trust",
        sso_url: "https://adfs.example.com/adfs/ls/",
        certificate: "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----"
      }

      assert {:ok, provider} = Sso.create_saml_provider(attrs)
      assert provider.name == "ADFS"
      assert provider.entity_id == "https://adfs.example.com/adfs/services/trust"
      assert provider.auto_provision == true
      assert provider.default_role == "reader"
    end

    test "lists SAML providers for an org", %{org: org} do
      {:ok, _} =
        Sso.create_saml_provider(%{
          org_id: org.id,
          name: "ADFS",
          entity_id: "https://adfs.example.com",
          sso_url: "https://adfs.example.com/adfs/ls/",
          certificate: "cert-data"
        })

      providers = Sso.list_saml_providers(org.id)
      assert length(providers) == 1
    end

    test "enforces unique entity_id per org", %{org: org} do
      attrs = %{
        org_id: org.id,
        name: "ADFS",
        entity_id: "https://adfs.example.com",
        sso_url: "https://adfs.example.com/adfs/ls/",
        certificate: "cert-data"
      }

      assert {:ok, _} = Sso.create_saml_provider(attrs)
      assert {:error, changeset} = Sso.create_saml_provider(%{attrs | name: "ADFS 2"})
      assert "has already been taken" in errors_on(changeset).org_id
    end
  end

  describe "SSO user provisioning" do
    test "provisions a new user via OIDC SSO", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration",
          default_role: "operator"
        })

      user_info = %{
        sub: "okta-user-123",
        email: "sso-user@example.com",
        name: "SSO User",
        groups: []
      }

      assert {:ok, user} = Sso.process_sso_login(:oidc, provider, user_info)
      assert user.email == "sso-user@example.com"
      assert user.role == "operator"
      assert user.sso_provider_type == "oidc"
      assert user.sso_provider_id == provider.id
      assert user.sso_subject == "okta-user-123"
      assert user.sso_provisioned_at != nil
      assert user.confirmed_at != nil
    end

    test "finds existing SSO user on repeat login", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration"
        })

      user_info = %{sub: "repeat-user", email: "repeat@example.com", groups: []}

      {:ok, user1} = Sso.process_sso_login(:oidc, provider, user_info)
      {:ok, user2} = Sso.process_sso_login(:oidc, provider, user_info)
      assert user1.id == user2.id
    end

    test "respects group → role mapping", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration",
          default_role: "reader",
          group_mapping: %{"zentinel-admins" => "admin", "zentinel-ops" => "operator"}
        })

      admin_info = %{sub: "admin1", email: "admin@example.com", groups: ["zentinel-admins"]}
      {:ok, admin} = Sso.process_sso_login(:oidc, provider, admin_info)
      assert admin.role == "admin"

      ops_info = %{sub: "ops1", email: "ops@example.com", groups: ["zentinel-ops"]}
      {:ok, ops} = Sso.process_sso_login(:oidc, provider, ops_info)
      assert ops.role == "operator"

      reader_info = %{sub: "reader1", email: "reader@example.com", groups: ["other-group"]}
      {:ok, reader} = Sso.process_sso_login(:oidc, provider, reader_info)
      assert reader.role == "reader"
    end

    test "rejects login when auto_provision is false and user doesn't exist", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Strict IdP",
          issuer: "https://strict.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://strict.example.com/.well-known/openid-configuration",
          auto_provision: false
        })

      user_info = %{sub: "new-user", email: "new@example.com", groups: []}
      assert {:error, :user_not_provisioned} = Sso.process_sso_login(:oidc, provider, user_info)
    end
  end

  describe "list_sso_providers_for_org/1" do
    test "returns both OIDC and SAML providers", %{org: org} do
      {:ok, _} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Okta",
          issuer: "https://okta.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://okta.example.com/.well-known/openid-configuration"
        })

      {:ok, _} =
        Sso.create_saml_provider(%{
          org_id: org.id,
          name: "ADFS",
          entity_id: "https://adfs.example.com",
          sso_url: "https://adfs.example.com/adfs/ls/",
          certificate: "cert-data"
        })

      providers = Sso.list_sso_providers_for_org(org.id)
      assert length(providers) == 2
      types = Enum.map(providers, fn {type, _, _} -> type end)
      assert "oidc" in types
      assert "saml" in types
    end

    test "excludes disabled providers", %{org: org} do
      {:ok, provider} =
        Sso.create_oidc_provider(%{
          org_id: org.id,
          name: "Disabled",
          issuer: "https://disabled.example.com",
          client_id: "c1",
          client_secret: "s1",
          discovery_url: "https://disabled.example.com/.well-known/openid-configuration"
        })

      Sso.update_oidc_provider(provider, %{enabled: false})

      providers = Sso.list_sso_providers_for_org(org.id)
      assert providers == []
    end
  end

  describe "password_login_allowed_for_user?/1" do
    test "allows password login for non-SSO users" do
      user = user_fixture()
      assert Sso.password_login_allowed_for_user?(user) == true
    end
  end
end
