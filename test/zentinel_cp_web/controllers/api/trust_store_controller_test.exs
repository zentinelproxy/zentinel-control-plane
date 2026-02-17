defmodule ZentinelCpWeb.Api.TrustStoreControllerTest do
  use ZentinelCpWeb.ConnCase

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.CertificateFixtures
  import ZentinelCp.TrustStoreFixtures

  describe "GET /api/v1/projects/:project_slug/trust-stores" do
    test "lists trust stores for project", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      trust_store_fixture(project: project, name: "Internal CA")

      conn = get(conn, "/api/v1/projects/#{project.slug}/trust-stores")

      assert %{"trust_stores" => stores, "total" => 1} = json_response(conn, 200)
      assert length(stores) == 1
      assert hd(stores)["name"] == "Internal CA"
    end

    test "returns empty list when no trust stores", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn = get(conn, "/api/v1/projects/#{project.slug}/trust-stores")

      assert %{"trust_stores" => [], "total" => 0} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/projects/:project_slug/trust-stores/:id" do
    test "shows a trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      ts = trust_store_fixture(project: project, name: "My CA")

      conn = get(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{ts.id}")

      assert %{"trust_store" => store} = json_response(conn, 200)
      assert store["name"] == "My CA"
      assert store["cert_count"] == 1
    end

    test "returns 404 for nonexistent trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn = get(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/v1/projects/:project_slug/trust-stores" do
    test "creates a trust store with valid PEM", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/trust-stores", %{
          "name" => "New CA Bundle",
          "certificates_pem" => test_cert_pem()
        })

      assert %{"trust_store" => store} = json_response(conn, 201)
      assert store["name"] == "New CA Bundle"
      assert store["slug"] == "new-ca-bundle"
      assert store["cert_count"] == 1
    end

    test "returns 422 for invalid PEM", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/trust-stores", %{
          "name" => "Bad",
          "certificates_pem" => "not-a-pem"
        })

      assert json_response(conn, 422)["error"] != nil
    end

    test "returns 422 for missing name", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn =
        post(conn, "/api/v1/projects/#{project.slug}/trust-stores", %{
          "certificates_pem" => test_cert_pem()
        })

      assert json_response(conn, 422)["error"] != nil
    end
  end

  describe "PUT /api/v1/projects/:project_slug/trust-stores/:id" do
    test "updates a trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      ts = trust_store_fixture(project: project)

      conn =
        put(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{ts.id}", %{
          "name" => "Updated Name"
        })

      assert %{"trust_store" => store} = json_response(conn, 200)
      assert store["name"] == "Updated Name"
    end

    test "returns 404 for nonexistent trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn =
        put(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{Ecto.UUID.generate()}", %{
          "name" => "Nope"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "DELETE /api/v1/projects/:project_slug/trust-stores/:id" do
    test "deletes a trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      ts = trust_store_fixture(project: project)

      conn = delete(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{ts.id}")

      assert response(conn, 204)
    end

    test "returns 404 for nonexistent trust store", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)

      conn = delete(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "GET /api/v1/projects/:project_slug/trust-stores/:id/download" do
    test "downloads PEM file", %{conn: conn} do
      project = project_fixture()
      {conn, _api_key} = authenticate_api(conn, project: project)
      ts = trust_store_fixture(project: project, name: "Download Test")

      conn = get(conn, "/api/v1/projects/#{project.slug}/trust-stores/#{ts.id}/download")

      assert response(conn, 200) == test_cert_pem()
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-pem-file"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "download-test.pem"
    end
  end
end
