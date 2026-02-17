defmodule ZentinelCpWeb.Api.InternalCaControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.InternalCaFixtures

  describe "GET /api/v1/projects/:project_slug/internal-ca" do
    test "returns CA when it exists", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      ca = internal_ca_fixture(project: project, name: "My CA")

      conn = get(conn, "/api/v1/projects/#{project.slug}/internal-ca")

      assert %{"internal_ca" => data} = json_response(conn, 200)
      assert data["name"] == "My CA"
      assert data["id"] == ca.id
    end

    test "returns 404 when no CA exists", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)

      conn = get(conn, "/api/v1/projects/#{project.slug}/internal-ca")

      assert json_response(conn, 404)["error"] =~ "No internal CA"
    end
  end

  describe "POST /api/v1/projects/:project_slug/internal-ca" do
    test "initializes a new CA", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/internal-ca", %{
          "name" => "Test CA",
          "subject_cn" => "My Internal CA",
          "key_algorithm" => "EC-P384"
        })

      assert %{"internal_ca" => data} = json_response(conn, 201)
      assert data["name"] == "Test CA"
      assert data["subject_cn"] == "My Internal CA"
      assert data["key_algorithm"] == "EC-P384"
      assert data["status"] == "active"
      assert data["fingerprint_sha256"] != nil
    end

    test "returns 422 when CA already exists", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      internal_ca_fixture(project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/internal-ca", %{
          "name" => "Second CA",
          "subject_cn" => "CN"
        })

      assert json_response(conn, 422)["error"] != nil
    end
  end

  describe "DELETE /api/v1/projects/:project_slug/internal-ca" do
    test "destroys the CA", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      internal_ca_fixture(project: project)

      conn = delete(conn, "/api/v1/projects/#{project.slug}/internal-ca")

      assert response(conn, 204)
    end

    test "returns 404 when no CA exists", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)

      conn = delete(conn, "/api/v1/projects/#{project.slug}/internal-ca")

      assert json_response(conn, 404)["error"] =~ "No internal CA"
    end
  end

  describe "GET /api/v1/projects/:project_slug/internal-ca/ca.pem" do
    test "downloads CA certificate", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      internal_ca_fixture(project: project)

      conn = get(conn, "/api/v1/projects/#{project.slug}/internal-ca/ca.pem")

      body = response(conn, 200)
      assert body =~ "-----BEGIN CERTIFICATE-----"
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-pem-file"
    end
  end

  describe "GET /api/v1/projects/:project_slug/internal-ca/certificates" do
    test "lists issued certificates", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      ca = internal_ca_fixture(project: project)
      issued_certificate_fixture(internal_ca: ca, name: "Client 1")

      conn = get(conn, "/api/v1/projects/#{project.slug}/internal-ca/certificates")

      assert %{"certificates" => certs, "total" => 1} = json_response(conn, 200)
      assert length(certs) == 1
      assert hd(certs)["name"] == "Client 1"
    end
  end

  describe "POST /api/v1/projects/:project_slug/internal-ca/certificates" do
    test "issues a new certificate", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      internal_ca_fixture(project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/internal-ca/certificates", %{
          "name" => "Service A",
          "subject_cn" => "service-a.example.com"
        })

      assert %{"certificate" => cert} = json_response(conn, 201)
      assert cert["name"] == "Service A"
      assert cert["subject_cn"] == "service-a.example.com"
      assert cert["serial_number"] == 1
      assert cert["status"] == "active"
    end
  end

  describe "POST /api/v1/projects/:project_slug/internal-ca/certificates/:id/revoke" do
    test "revokes a certificate", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      ca = internal_ca_fixture(project: project)
      cert = issued_certificate_fixture(internal_ca: ca)

      conn =
        post(
          conn,
          "/api/v1/projects/#{project.slug}/internal-ca/certificates/#{cert.id}/revoke",
          %{"reason" => "keyCompromise"}
        )

      assert %{"certificate" => data} = json_response(conn, 200)
      assert data["status"] == "revoked"
      assert data["revoke_reason"] == "keyCompromise"
    end
  end

  describe "GET /api/v1/projects/:project_slug/internal-ca/certificates/:id" do
    test "shows a certificate", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      ca = internal_ca_fixture(project: project)
      cert = issued_certificate_fixture(internal_ca: ca, name: "Show Me")

      conn =
        get(conn, "/api/v1/projects/#{project.slug}/internal-ca/certificates/#{cert.id}")

      assert %{"certificate" => data} = json_response(conn, 200)
      assert data["name"] == "Show Me"
    end

    test "returns 404 for nonexistent certificate", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      internal_ca_fixture(project: project)

      conn =
        get(
          conn,
          "/api/v1/projects/#{project.slug}/internal-ca/certificates/#{Ecto.UUID.generate()}"
        )

      assert json_response(conn, 404)["error"] =~ "Not found"
    end
  end

  describe "GET /api/v1/projects/:project_slug/internal-ca/certificates/:id/download" do
    test "downloads certificate and key", %{conn: conn} do
      project = project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      ca = internal_ca_fixture(project: project)
      cert = issued_certificate_fixture(internal_ca: ca)

      conn =
        get(conn, "/api/v1/projects/#{project.slug}/internal-ca/certificates/#{cert.id}/download")

      assert %{
               "certificate_pem" => cert_pem,
               "private_key_pem" => key_pem,
               "ca_cert_pem" => ca_pem
             } =
               json_response(conn, 200)

      assert cert_pem =~ "-----BEGIN CERTIFICATE-----"
      assert key_pem =~ "-----BEGIN"
      assert ca_pem =~ "-----BEGIN CERTIFICATE-----"
    end
  end
end
