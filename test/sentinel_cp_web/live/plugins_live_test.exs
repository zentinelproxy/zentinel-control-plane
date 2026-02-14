defmodule SentinelCpWeb.PluginsLiveTest do
  use SentinelCpWeb.ConnCase

  import Phoenix.LiveViewTest
  import SentinelCp.AccountsFixtures
  import SentinelCp.ProjectsFixtures
  import SentinelCp.PluginFixtures

  setup %{conn: conn} do
    user = user_fixture()
    project = project_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user, project: project}
  end

  describe "Index" do
    test "lists plugins", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project, name: "Test Plugin"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins")

      assert html =~ "Plugins"
      assert html =~ plugin.name
    end

    test "shows empty state", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins")

      assert html =~ "No plugins yet"
    end

    test "deletes plugin", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project, name: "To Delete"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/plugins")

      view
      |> element("button[phx-value-id='#{plugin.id}']")
      |> render_click()

      refute render(view) =~ "To Delete"
    end
  end

  describe "New" do
    test "renders form", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins/new")

      assert html =~ "Create Plugin"
      assert html =~ "wasm"
      assert html =~ "lua"
    end

    test "creates plugin and navigates", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/plugins/new")

      view
      |> form("form", %{
        "name" => "New Plugin",
        "plugin_type" => "wasm",
        "enabled" => "true"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "plugins"
    end
  end

  describe "Show" do
    test "displays plugin details", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project, name: "Show Plugin"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins/#{plugin.id}")

      assert html =~ "Show Plugin"
      assert html =~ plugin.plugin_type
    end

    test "shows version history", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})
      _version = plugin_version_fixture(%{plugin: plugin, version: "1.0.0"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins/#{plugin.id}")

      assert html =~ "1.0.0"
      assert html =~ "Versions"
    end
  end

  describe "Edit" do
    test "renders edit form", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project, name: "Editable"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/plugins/#{plugin.id}/edit")

      assert html =~ "Edit Plugin"
      assert html =~ "Editable"
    end

    test "updates plugin and navigates", %{conn: conn, project: project} do
      plugin = plugin_fixture(%{project: project})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/plugins/#{plugin.id}/edit")

      view
      |> form("form", %{
        "name" => "Updated Plugin",
        "enabled" => "true"
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "plugins"
    end
  end
end
