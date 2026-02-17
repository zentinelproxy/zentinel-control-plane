defmodule ZentinelCpWeb.CertificatesLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.CertificateFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "CertificatesLive.Index" do
    test "renders certificates list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/certificates")
      assert html =~ "Certificates"
    end

    test "shows certificates", %{conn: conn, project: project} do
      _cert = certificate_fixture(project: project, name: "My Test Cert")
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/certificates")
      assert html =~ "My Test Cert"
    end

    test "shows empty state when no certificates", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/certificates")
      assert html =~ "No certificates yet"
    end

    test "shows certificate status badge", %{conn: conn, project: project} do
      _cert = certificate_fixture(project: project, name: "Active Cert")
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/certificates")
      assert html =~ "active"
    end
  end

  describe "CertificatesLive.New" do
    test "renders upload form", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/certificates/new")
      assert html =~ "Upload Certificate"
    end

    test "creates a certificate", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/certificates/new")

      view
      |> form("form", %{
        "name" => "New Cert",
        "domain" => "new.example.com",
        "cert_pem" => test_cert_pem(),
        "key_pem" => test_key_pem()
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/certificates/"
    end
  end

  describe "CertificatesLive.Show" do
    test "renders certificate detail page", %{conn: conn, project: project} do
      cert = certificate_fixture(project: project, name: "Detail Cert")

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/certificates/#{cert.id}")

      assert html =~ "Detail Cert"
      assert html =~ cert.domain
      assert html =~ "active"
    end

    test "shows fingerprint", %{conn: conn, project: project} do
      cert = certificate_fixture(project: project)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/certificates/#{cert.id}")

      assert html =~ "SHA-256"
      assert html =~ cert.fingerprint_sha256
    end
  end

  describe "CertificatesLive.Edit" do
    test "renders edit form", %{conn: conn, project: project} do
      cert = certificate_fixture(project: project, name: "Edit Me")

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/certificates/#{cert.id}/edit")

      assert html =~ "Edit Certificate"
      assert html =~ "Edit Me"
    end

    test "updates a certificate", %{conn: conn, project: project} do
      cert = certificate_fixture(project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.slug}/certificates/#{cert.id}/edit")

      view
      |> form("form", %{"name" => "Updated Cert Name", "status" => "active"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/certificates/"
    end
  end
end
