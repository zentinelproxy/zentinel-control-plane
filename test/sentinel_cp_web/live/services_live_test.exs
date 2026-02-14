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

    test "shows type column with badge", %{conn: conn, project: project} do
      _service =
        service_fixture(%{
          project: project,
          name: "graphql-svc",
          service_type: "graphql",
          graphql: %{"max_depth" => 10}
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services")
      assert html =~ "graphql"
    end

    test "shows standard type for default services", %{conn: conn, project: project} do
      _service = service_fixture(%{project: project})
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services")
      assert html =~ "standard"
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

    test "service type selector renders all options", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      assert html =~ ~s(value="standard")
      assert html =~ ~s(value="graphql")
      assert html =~ ~s(value="grpc")
      assert html =~ ~s(value="websocket")
      assert html =~ ~s(value="streaming")
      assert html =~ ~s(value="inference")
    end

    test "graphql config section appears when graphql type selected", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      render_click(view, "switch_service_type", %{"service_type" => "graphql"})
      html = render(view)

      assert html =~ "GraphQL Settings"
      assert html =~ "Max Depth"
      assert html =~ "Max Complexity"
      assert html =~ "Introspection"
      assert html =~ "Playground Path"
    end

    test "grpc config section appears when grpc type selected", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      render_click(view, "switch_service_type", %{"service_type" => "grpc"})
      html = render(view)

      assert html =~ "gRPC Settings"
      assert html =~ "Max Message Size"
      assert html =~ "Reflection"
      assert html =~ "Health Check Service"
      assert html =~ "Allowed Services"
    end

    test "creates graphql service with protocol config", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      # Select graphql type
      render_click(view, "switch_service_type", %{"service_type" => "graphql"})

      view
      |> form("form[phx-submit='create_service']", %{
        "name" => "GraphQL API",
        "route_path" => "/graphql",
        "upstream_url" => "http://graphql:4000",
        "graphql" => %{
          "max_depth" => "10",
          "max_complexity" => "1000",
          "playground_path" => "/playground"
        }
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/services/"

      # Verify the service was created with correct type
      [service] = SentinelCp.Services.list_services(project.id)
      assert service.service_type == "graphql"
      assert service.graphql["max_depth"] == 10
    end

    test "creates grpc service with protocol config", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/services/new")

      render_click(view, "switch_service_type", %{"service_type" => "grpc"})

      view
      |> form("form[phx-submit='create_service']", %{
        "name" => "gRPC API",
        "route_path" => "/grpc/*",
        "upstream_url" => "http://grpc:50051",
        "grpc" => %{
          "max_message_size" => "4194304",
          "health_check_service" => "grpc.health.v1.Health"
        }
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

    test "shows service type badge", %{conn: conn, project: project} do
      service =
        service_fixture(%{
          project: project,
          service_type: "graphql",
          graphql: %{"max_depth" => 10}
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      assert html =~ "graphql"
    end

    test "shows protocol config section for graphql service", %{conn: conn, project: project} do
      service =
        service_fixture(%{
          project: project,
          service_type: "graphql",
          graphql: %{"max_depth" => 10, "max_complexity" => 1000}
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      assert html =~ "Protocol Configuration"
      assert html =~ "Max Depth"
    end

    test "does not show protocol config for standard service", %{conn: conn, project: project} do
      service = service_fixture(%{project: project})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}")

      refute html =~ "Protocol Configuration"
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

    test "edit pre-populates service type", %{conn: conn, project: project} do
      service =
        service_fixture(%{
          project: project,
          service_type: "graphql",
          graphql: %{"max_depth" => 10}
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}/edit")

      assert html =~ "Service Type"
      # The selected option should be graphql
      assert html =~ "graphql"
    end

    test "edit pre-populates graphql config", %{conn: conn, project: project} do
      service =
        service_fixture(%{
          project: project,
          service_type: "graphql",
          graphql: %{"max_depth" => 15, "playground_path" => "/gql"}
        })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.slug}/services/#{service.id}/edit")

      assert html =~ "GraphQL Settings"
      assert html =~ "15"
      assert html =~ "/gql"
    end
  end
end
