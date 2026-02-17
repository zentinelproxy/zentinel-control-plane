defmodule ZentinelCpWeb.SlosLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.Observability

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "SLO Index" do
    test "renders empty state", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/slos")

      assert html =~ "Service Level Objectives"
      assert html =~ "No SLOs defined yet"
    end

    test "lists SLOs", %{conn: conn, project: project} do
      {:ok, _slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "API Availability",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/slos")

      assert html =~ "API Availability"
      assert html =~ "availability"
      assert html =~ "99.9"
    end

    test "deletes an SLO", %{conn: conn, project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "To Delete",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/slos")

      assert render(view) =~ "To Delete"

      render_click(view, "delete", %{"id" => slo.id})

      refute render(view) =~ "To Delete"
    end
  end

  describe "SLO New" do
    test "creates an SLO via form", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/slos/new")

      assert html =~ "New SLO"

      view
      |> form("form", %{
        "name" => "New Avail SLO",
        "sli_type" => "availability",
        "target" => "99.9",
        "window_days" => "30"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/slos/"
    end
  end

  describe "SLO Show" do
    test "displays SLO details", %{conn: conn, project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Show SLO",
          sli_type: "error_rate",
          target: 1.0,
          window_days: 7
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/slos/#{slo.id}")

      assert html =~ "Show SLO"
      assert html =~ "error_rate"
      assert html =~ "Error Budget"
      assert html =~ "Burn Rate"
    end

    test "toggles enabled state", %{conn: conn, project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Toggle SLO",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/slos/#{slo.id}")

      assert html =~ "enabled"

      render_click(view, "toggle_enabled", %{})

      assert render(view) =~ "disabled"
    end
  end

  describe "SLO Edit" do
    test "updates an SLO", %{conn: conn, project: project} do
      {:ok, slo} =
        Observability.create_slo(%{
          project_id: project.id,
          name: "Edit SLO",
          sli_type: "availability",
          target: 99.9
        })

      {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/slos/#{slo.id}/edit")

      assert html =~ "Edit SLO"

      view
      |> form("form", %{
        "name" => "Updated SLO",
        "sli_type" => "availability",
        "target" => "99.5",
        "window_days" => "14"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/slos/"

      updated = Observability.get_slo!(slo.id)
      assert updated.name == "Updated SLO"
      assert updated.target == 99.5
    end
  end
end
