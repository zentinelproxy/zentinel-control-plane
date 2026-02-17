defmodule ZentinelCpWeb.AuditLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures

  setup %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "AuditLive.Index" do
    test "renders audit log page for admin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/audit")
      assert html =~ "Audit"
    end

    test "redirects non-admin users" do
      user = user_fixture(%{role: "operator"})
      conn = build_conn() |> log_in_user(user)
      assert {:error, {:redirect, %{to: "/projects"}}} = live(conn, ~p"/audit")
    end

    test "shows audit log entries", %{conn: conn, admin: admin} do
      ZentinelCp.Audit.log_user_action(admin, "test.action", "test", Ecto.UUID.generate(),
        changes: %{foo: "bar"}
      )

      {:ok, _view, html} = live(conn, ~p"/audit")
      assert html =~ "test.action"
    end
  end
end
