defmodule ZentinelCpWeb.Security.PortalAccessTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures

  alias ZentinelCp.{Orgs, Projects}

  defp portal_project(mode) do
    org = ZentinelCp.OrgsFixtures.org_fixture()
    project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: org})
    {:ok, project} = Projects.update_project(project, %{settings: %{"portal_access" => mode}})
    {org, project}
  end

  defp member(org) do
    user = user_fixture()
    {:ok, _} = Orgs.add_member(org, user, "reader")
    user
  end

  test "a public portal is open to anonymous visitors", %{conn: conn} do
    {_org, project} = portal_project("public")
    assert {:ok, _view, html} = live(conn, "/portal/#{project.slug}")
    assert html =~ "API Documentation"
  end

  test "joining from another page does not skip the portal check", %{conn: conn} do
    {_org, project} = portal_project("authenticated")
    {:ok, view, _} = live(conn, "/login")

    assert {:error, {:redirect, %{to: "/login"}}} =
             live_redirect(view, to: "/portal/#{project.slug}")
  end

  test "a disabled portal is not found", %{conn: conn} do
    {_org, project} = portal_project("disabled")
    assert get(conn, "/portal/#{project.slug}").status == 404

    {:ok, view, _} = live(conn, "/login")

    exit_reason = catch_exit(live_redirect(view, to: "/portal/#{project.slug}"))
    assert inspect(exit_reason) =~ "status: 404"
  end

  test "an authenticated portal needs a member of the org", %{conn: conn} do
    {org, project} = portal_project("authenticated")

    assert redirected_to(get(conn, "/portal/#{project.slug}")) == "/login"

    outsider = conn |> log_in_user(user_fixture()) |> get("/portal/#{project.slug}")
    assert redirected_to(outsider) == "/login"

    assert {:ok, _view, _html} =
             conn |> log_in_user(member(org)) |> live("/portal/#{project.slug}")
  end

  test "the console and keys need a member even on a public portal", %{conn: conn} do
    {org, project} = portal_project("public")

    for page <- ["console", "keys"] do
      assert {:error, {:redirect, %{to: "/login"}}} =
               live(conn, "/portal/#{project.slug}/#{page}")

      assert {:error, {:redirect, %{to: "/login"}}} =
               conn |> log_in_user(user_fixture()) |> live("/portal/#{project.slug}/#{page}")

      assert {:ok, _view, _html} =
               conn |> log_in_user(member(org)) |> live("/portal/#{project.slug}/#{page}")
    end
  end

  test "docs do not show another project's spec", %{conn: conn} do
    {_org, project} = portal_project("public")
    {_other_org, other} = portal_project("public")

    spec = ZentinelCp.OpenApiFixtures.openapi_spec_fixture(%{project: other})
    [path | _] = Map.keys(spec.spec_data["paths"])

    {:ok, _view, html} = live(conn, "/portal/#{project.slug}/docs/#{spec.id}")
    refute html =~ path
  end
end
