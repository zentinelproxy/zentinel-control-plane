defmodule ZentinelCpWeb.Integration.Api.CertificateWorkflowTest do
  @moduledoc """
  Integration tests for certificate API workflows.
  """
  use ZentinelCpWeb.IntegrationCase

  import ZentinelCp.CertificateFixtures

  @moduletag :integration

  describe "certificate CRUD workflow" do
    test "create → list → show → update → delete", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      # Create
      create_resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/certificates", %{
          name: "API TLS Cert",
          domain: "api.example.com",
          cert_pem: test_cert_pem(),
          key_pem: test_key_pem()
        })
        |> json_response!(201)

      assert create_resp["certificate"]["id"]
      assert create_resp["certificate"]["name"] == "API TLS Cert"
      assert create_resp["certificate"]["slug"] == "api-tls-cert"
      assert create_resp["certificate"]["domain"] == "api.example.com"
      assert create_resp["certificate"]["status"] == "active"
      assert create_resp["certificate"]["fingerprint_sha256"] != nil

      cert_id = create_resp["certificate"]["id"]

      # List
      list_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/certificates")
        |> json_response!(200)

      assert list_resp["total"] >= 1
      assert Enum.any?(list_resp["certificates"], &(&1["id"] == cert_id))

      # Show
      show_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/certificates/#{cert_id}")
        |> json_response!(200)

      assert show_resp["certificate"]["id"] == cert_id
      assert show_resp["certificate"]["domain"] == "api.example.com"

      # Update
      update_resp =
        api_conn
        |> put("/api/v1/projects/#{project_slug}/certificates/#{cert_id}", %{
          name: "Updated TLS Cert",
          auto_renew: true
        })
        |> json_response!(200)

      assert update_resp["certificate"]["name"] == "Updated TLS Cert"
      assert update_resp["certificate"]["auto_renew"] == true

      # Download (cert PEM only, not key)
      download_resp =
        api_conn
        |> get("/api/v1/projects/#{project_slug}/certificates/#{cert_id}/download")

      assert download_resp.status == 200
      assert download_resp.resp_body =~ "BEGIN CERTIFICATE"
      refute download_resp.resp_body =~ "PRIVATE KEY"

      # Delete
      api_conn
      |> delete("/api/v1/projects/#{project_slug}/certificates/#{cert_id}")
      |> response(204)

      # Verify deleted
      api_conn
      |> get("/api/v1/projects/#{project_slug}/certificates/#{cert_id}")
      |> json_response!(404)
    end

    test "rejects certificate with invalid PEM", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/certificates", %{
          name: "Bad Cert",
          domain: "bad.example.com",
          cert_pem: "not-valid-pem",
          key_pem: test_key_pem()
        })
        |> json_response!(422)

      assert resp["error"]["cert_pem"] != nil
    end

    test "rejects certificate without private key", %{conn: conn} do
      {api_conn, context} =
        setup_api_context(conn, scopes: ["services:read", "services:write"])

      project_slug = context.project.slug

      resp =
        api_conn
        |> post("/api/v1/projects/#{project_slug}/certificates", %{
          name: "No Key",
          domain: "nokey.example.com",
          cert_pem: test_cert_pem()
        })
        |> json_response!(422)

      assert resp["error"]["key_pem_encrypted"] != nil
    end
  end
end
