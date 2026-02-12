defmodule SentinelCpWeb.ServicesLiveTest do
  use SentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.ProjectsFixtures
  import SentinelCp.ServicesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "ServicesLive.Index" do
    test "renders services list page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services")
      assert html =~ "Services"
    end

    test "shows services", %{conn: conn, project: project} do
      _service = service_fixture(%{project: project, name: "my-test-svc"})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services")
      assert html =~ "my-test-svc"
    end

    test "shows empty state when no services", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services")
      assert html =~ "No services yet"
    end

    test "deletes a service", %{conn: conn, project: project} do
      service = service_fixture(%{project: project, name: "to-delete"})
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services")

      # The delete button has data-confirm, so we call the event directly
      render_click(view, "delete", %{"id" => service.id})

      html = render(view)
      refute html =~ "to-delete"
    end

    test "toggles service enabled state", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services")

      render_click(view, "toggle_enabled", %{"id" => service.id})

      assert has_element?(view, "table")
    end
  end

  describe "ServicesLive.New" do
    test "renders new service form", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services/new")
      assert html =~ "Create Service"
    end

    test "creates a service", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      view
      |> form("form[phx-submit='create_service']", %{
        "name" => "New API",
        "route_path" => "/api/v2/*",
        "upstream_url" => "http://api:9090"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/services/"
    end
  end

  describe "ServicesLive.Show" do
    test "renders service detail page", %{conn: conn, project: project} do
      service = service_fixture(%{project: project, name: "Detail Service"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      assert html =~ "Detail Service"
      assert html =~ service.route_path
    end

    test "shows KDL preview", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      assert html =~ "KDL Preview"
      assert html =~ "route"
    end

    test "deletes service from show page", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      render_click(view, "delete")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/services"
    end
  end

  describe "ServicesLive.Edit" do
    test "renders edit form", %{conn: conn, project: project} do
      service = service_fixture(%{project: project, name: "Edit Me"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}/edit")

      assert html =~ "Edit Service"
      assert html =~ "Edit Me"
    end

    test "updates a service", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}/edit")

      view
      |> form("form", %{
        "name" => "Updated Name",
        "route_path" => "/updated/*",
        "upstream_url" => "http://updated:8080"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/services/"
    end
  end
end
