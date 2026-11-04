defmodule ZentinelCpWeb.Security.LiveviewAccessTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.OrgsFixtures
  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.Orgs

  defp project_in_org do
    org = org_fixture()
    {org, project_fixture(%{org: org})}
  end

  defp member(org, role) do
    user = user_fixture()
    {:ok, _} = Orgs.add_member(org, user, role)
    user
  end

  test "an anonymous visitor cannot live-navigate from /login to a project page", %{conn: conn} do
    {_org, project} = project_in_org()
    {:ok, view, _html} = live(conn, "/login")

    assert {:error, {:redirect, %{to: "/login"}}} =
             live_redirect(view, to: "/projects/#{project.slug}/nodes")
  end

  test "a non-member cannot open another org's project", %{conn: conn} do
    {_org, project} = project_in_org()
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/orgs"}}} = live(conn, "/projects/#{project.slug}/nodes")
  end

  test "a non-member cannot open another org's settings", %{conn: conn} do
    {org, _project} = project_in_org()
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/orgs"}}} = live(conn, "/orgs/#{org.slug}")
  end

  test "an org in the URL must own the project", %{conn: conn} do
    {own_org, _} = project_in_org()
    {_other_org, other_project} = project_in_org()
    conn = log_in_user(conn, member(own_org, "admin"))

    assert {:error, {:redirect, %{to: "/orgs"}}} =
             live(conn, "/orgs/#{own_org.slug}/projects/#{other_project.slug}/nodes")
  end

  test "a member can open their project", %{conn: conn} do
    {org, project} = project_in_org()
    conn = log_in_user(conn, member(org, "operator"))

    assert {:ok, _view, _html} = live(conn, "/projects/#{project.slug}/nodes")
  end

  test "a reader's write events are blocked", %{conn: conn} do
    {org, project} = project_in_org()
    node = ZentinelCp.NodesFixtures.node_fixture(%{project: project})
    conn = log_in_user(conn, member(org, "reader"))

    {:ok, view, _html} = live(conn, "/projects/#{project.slug}/nodes")

    render_click(view, "delete", %{"id" => node.id})
    assert ZentinelCp.Nodes.get_node(node.id)
  end

  test "a reader's read-only events still work", %{conn: conn} do
    {org, project} = project_in_org()
    conn = log_in_user(conn, member(org, "reader"))

    {:ok, view, _html} = live(conn, "/projects/#{project.slug}/nodes")

    assert render_click(view, "toggle_form", %{}) =~ "form"
  end

  test "a global admin can open any project", %{conn: conn} do
    {_org, project} = project_in_org()
    conn = log_in_user(conn, admin_fixture())

    assert {:ok, _view, _html} = live(conn, "/projects/#{project.slug}/nodes")
  end
end
