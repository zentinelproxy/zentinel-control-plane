defmodule ZentinelCpWeb.ApiKeysLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures

  setup %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "ApiKeysLive.Index" do
    test "renders API keys page for admin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/api-keys")
      assert html =~ "API Keys"
    end

    test "allows operator users to view", %{conn: _conn} do
      user = user_fixture(%{role: "operator"})
      conn = build_conn() |> log_in_user(user)
      {:ok, _view, html} = live(conn, ~p"/api-keys")
      assert html =~ "API Keys"
    end

    test "shows existing API keys", %{conn: conn, admin: admin} do
      project = project_fixture()
      _api_key = api_key_fixture(%{user: admin, project: project, name: "test-key"})

      {:ok, _view, html} = live(conn, ~p"/api-keys")
      assert html =~ "test-key"
      assert html =~ project.name
    end

    test "can create a new API key", %{conn: conn} do
      project = project_fixture()

      {:ok, view, _html} = live(conn, ~p"/api-keys")

      # Open create form
      view |> element("button", "New API Key") |> render_click()

      # Fill in the form and submit
      view
      |> form(~s|form[phx-submit="create_api_key"]|, %{
        "name" => "new-test-key",
        "project_id" => project.id
      })
      |> render_submit()

      # Should show success and display the new key
      html = render(view)
      assert html =~ "created" or html =~ "new-test-key"
    end

    test "can revoke an API key", %{conn: conn, admin: admin} do
      project = project_fixture()
      api_key = api_key_fixture(%{user: admin, project: project, name: "key-to-revoke"})

      {:ok, view, _html} = live(conn, ~p"/api-keys")

      view
      |> element(~s|button[phx-click="revoke"][phx-value-id="#{api_key.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "revoked" or html =~ "Revoked"
    end

    test "can delete an API key", %{conn: conn, admin: admin} do
      project = project_fixture()
      api_key = api_key_fixture(%{user: admin, project: project, name: "key-to-delete"})

      {:ok, view, html} = live(conn, ~p"/api-keys")
      assert html =~ "key-to-delete"

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{api_key.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "deleted" or not (html =~ "key-to-delete")
    end

    test "shows API keys from multiple projects", %{conn: conn, admin: admin} do
      project1 = project_fixture(%{name: "Project Alpha"})
      project2 = project_fixture(%{name: "Project Beta"})
      _key1 = api_key_fixture(%{user: admin, project: project1, name: "alpha-key"})
      _key2 = api_key_fixture(%{user: admin, project: project2, name: "beta-key"})

      {:ok, _view, html} = live(conn, ~p"/api-keys")
      assert html =~ "alpha-key"
      assert html =~ "beta-key"
      assert html =~ "Project Alpha"
      assert html =~ "Project Beta"
    end
  end
end
