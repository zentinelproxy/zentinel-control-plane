defmodule ZentinelCp.Services.Acme.RenewalTest do
  use ZentinelCp.DataCase, async: false

  import Mox
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.CertificateFixtures

  alias ZentinelCp.Services
  alias ZentinelCp.Services.Acme.Renewal

  setup :verify_on_exit!

  setup do
    project = project_fixture()

    cert =
      certificate_fixture(
        project: project,
        auto_renew: true,
        acme_config: %{
          "email" => "test@example.com",
          "directory_url" => "https://acme-staging-v02.api.letsencrypt.org/directory"
        }
      )

    # Set acme_config via update since fixture doesn't pass it through
    {:ok, cert} =
      Services.update_certificate(cert, %{
        auto_renew: true,
        acme_config: %{
          "email" => "test@example.com",
          "directory_url" => "https://acme-staging-v02.api.letsencrypt.org/directory"
        }
      })

    %{project: project, cert: cert}
  end

  describe "renew/1" do
    test "orchestrates full ACME flow with mocked client", %{cert: cert} do
      # Use the existing fixture cert PEM as the "new" cert from ACME
      new_cert_pem = test_cert_pem()

      mock = ZentinelCp.Services.Acme.Client.Mock

      mock
      |> expect(:get_directory, fn _url ->
        {:ok,
         %{
           "newNonce" => "https://acme.test/new-nonce",
           "newAccount" => "https://acme.test/new-acct",
           "newOrder" => "https://acme.test/new-order"
         }}
      end)
      |> expect(:new_nonce, fn _url -> {:ok, "nonce-1"} end)
      |> expect(:new_account, fn _url, _key, _nonce, _payload ->
        {:ok, %{kid: "https://acme.test/acct/123", nonce: "nonce-2"}}
      end)
      |> expect(:new_order, fn _url, _kid, _key, _nonce, domains ->
        assert "test.example.com" in domains

        {:ok,
         %{
           order_url: "https://acme.test/order/1",
           authorizations: ["https://acme.test/authz/1"],
           finalize_url: "https://acme.test/order/1/finalize",
           nonce: "nonce-3"
         }}
      end)
      |> expect(:get_authorization, fn _url, _kid, _key, _nonce ->
        {:ok,
         %{
           status: "pending",
           challenges: [
             %{
               "type" => "http-01",
               "url" => "https://acme.test/chall/1",
               "token" => "test-token-xyz"
             }
           ],
           nonce: "nonce-4"
         }}
      end)
      |> expect(:respond_challenge, fn _url, _kid, _key, _nonce ->
        {:ok, %{nonce: "nonce-5"}}
      end)
      |> expect(:poll_authorization, fn _url, _kid, _key, _nonce, _opts ->
        {:ok, %{status: "valid", nonce: "nonce-6"}}
      end)
      |> expect(:finalize_order, fn _url, _kid, _key, _nonce, csr_der ->
        assert is_binary(csr_der)
        {:ok, %{nonce: "nonce-7"}}
      end)
      |> expect(:poll_order, fn _url, _kid, _key, _nonce, _opts ->
        {:ok,
         %{
           status: "valid",
           certificate_url: "https://acme.test/cert/1",
           nonce: "nonce-8"
         }}
      end)
      |> expect(:download_certificate, fn _url, _kid, _key, _nonce ->
        {:ok, %{cert_pem: new_cert_pem, nonce: "nonce-9"}}
      end)

      assert {:ok, updated} = Renewal.renew(cert)
      assert updated.cert_pem == new_cert_pem
      assert updated.status == "active"
      assert updated.last_renewal_error == nil
      assert updated.last_renewal_at != nil
    end

    test "records error on ACME failure", %{cert: cert} do
      mock = ZentinelCp.Services.Acme.Client.Mock

      mock
      |> expect(:get_directory, fn _url ->
        {:error, :connection_failed}
      end)

      assert {:error, :connection_failed} = Renewal.renew(cert)

      # Check that the error was recorded
      updated = Services.get_certificate!(cert.id)
      assert updated.last_renewal_error != nil
      assert String.contains?(updated.last_renewal_error, "connection_failed")
    end

    test "handles already-valid authorization", %{cert: cert} do
      new_cert_pem = test_cert_pem()

      mock = ZentinelCp.Services.Acme.Client.Mock

      mock
      |> expect(:get_directory, fn _url ->
        {:ok,
         %{
           "newNonce" => "https://acme.test/new-nonce",
           "newAccount" => "https://acme.test/new-acct",
           "newOrder" => "https://acme.test/new-order"
         }}
      end)
      |> expect(:new_nonce, fn _url -> {:ok, "nonce-1"} end)
      |> expect(:new_account, fn _url, _key, _nonce, _payload ->
        {:ok, %{kid: "https://acme.test/acct/123", nonce: "nonce-2"}}
      end)
      |> expect(:new_order, fn _url, _kid, _key, _nonce, _domains ->
        {:ok,
         %{
           order_url: "https://acme.test/order/1",
           authorizations: ["https://acme.test/authz/1"],
           finalize_url: "https://acme.test/order/1/finalize",
           nonce: "nonce-3"
         }}
      end)
      |> expect(:get_authorization, fn _url, _kid, _key, _nonce ->
        {:ok, %{status: "valid", challenges: [], nonce: "nonce-4"}}
      end)
      |> expect(:finalize_order, fn _url, _kid, _key, _nonce, _csr ->
        {:ok, %{nonce: "nonce-5"}}
      end)
      |> expect(:poll_order, fn _url, _kid, _key, _nonce, _opts ->
        {:ok, %{status: "valid", certificate_url: "https://acme.test/cert/1", nonce: "nonce-6"}}
      end)
      |> expect(:download_certificate, fn _url, _kid, _key, _nonce ->
        {:ok, %{cert_pem: new_cert_pem, nonce: "nonce-7"}}
      end)

      assert {:ok, updated} = Renewal.renew(cert)
      assert updated.cert_pem == new_cert_pem
    end
  end
end
