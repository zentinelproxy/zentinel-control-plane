defmodule SentinelCp.Services.CertificateRenewalWorkerTest do
  use SentinelCp.DataCase, async: false

  import Mox
  import SentinelCp.ProjectsFixtures
  import SentinelCp.CertificateFixtures

  alias SentinelCp.Services
  alias SentinelCp.Services.CertificateRenewalWorker

  setup :verify_on_exit!

  setup do
    project = project_fixture()

    cert = certificate_fixture(project: project, auto_renew: true)

    # Set ACME config and make it look like it's expiring soon
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

  describe "perform/1" do
    test "finds and attempts to renew expiring certificates", %{cert: cert} do
      # The fixture cert expires in ~365 days, but list_acme_renewal_candidates
      # looks for certs expiring within 30 days. We need to adjust the cert's not_after.
      soon = DateTime.utc_now() |> DateTime.add(10 * 86_400, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(cert, %{not_after: soon})
      |> SentinelCp.Repo.update!()

      new_cert_pem = test_cert_pem()
      mock = SentinelCp.Services.Acme.Client.Mock

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

      assert :ok = CertificateRenewalWorker.perform(%Oban.Job{args: %{}})

      updated = Services.get_certificate!(cert.id)
      assert updated.cert_pem == new_cert_pem
      assert updated.last_renewal_at != nil
    end

    test "does not renew certificates that are not expiring soon", %{cert: _cert} do
      # The fixture cert has not_after ~365 days out, which is past the 30-day threshold.
      # No ACME calls should be made for it.
      # But we need to handle the fact that the cert from setup has acme_config.
      # Since not_after is far in the future, list_acme_renewal_candidates won't find it.
      assert :ok = CertificateRenewalWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not renew certificates without acme_config" do
      project = project_fixture()
      cert = certificate_fixture(project: project, auto_renew: true)

      # Don't set acme_config (it stays as %{})
      # Make it expiring soon
      soon = DateTime.utc_now() |> DateTime.add(10 * 86_400, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(cert, %{not_after: soon, auto_renew: true})
      |> SentinelCp.Repo.update!()

      # No ACME client calls should be made because acme_config is empty
      assert :ok = CertificateRenewalWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
