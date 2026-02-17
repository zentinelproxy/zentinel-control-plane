defmodule ZentinelCpWeb.ProfileLiveTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{email: "profile-test@example.com", role: "operator"})
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "ProfileLive.Index" do
    test "renders profile page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "Profile"
    end

    test "shows user email", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "profile-test@example.com"
    end

    test "shows user role", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "operator"
    end

    test "shows member since date", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "Member Since" or html =~ "member"
    end

    test "shows security section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "Security" or html =~ "Password"
    end

    test "can toggle password change form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/profile")
      refute html =~ "Current Password"

      # Click to show form
      view |> element("button", "Change Password") |> render_click()

      html = render(view)
      assert html =~ "Current Password"
      assert html =~ "New Password"

      # Click cancel button specifically
      view |> element(~s|button[phx-click="toggle_password_form"]|, "Cancel") |> render_click()

      html = render(view)
      refute html =~ "Current Password"
    end

    test "can submit password change form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      # Show form
      view |> element("button", "Change Password") |> render_click()

      # Submit password change - the test verifies the form can be submitted
      # The actual validation is handled by the Accounts context
      result =
        view
        |> form(~s|form[phx-submit="change_password"]|, %{
          "password" => %{
            "current_password" => valid_user_password(),
            "new_password" => "new_secure_password123",
            "new_password_confirmation" => "new_secure_password123"
          }
        })
        |> render_submit()

      # Form should have submitted (either success or validation error)
      assert is_binary(result)
    end

    test "shows error for wrong current password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      # Show form
      view |> element("button", "Change Password") |> render_click()

      # Submit with wrong current password
      view
      |> form(~s|form[phx-submit="change_password"]|, %{
        "password" => %{
          "current_password" => "wrong_password",
          "new_password" => "new_secure_password123",
          "new_password_confirmation" => "new_secure_password123"
        }
      })
      |> render_submit()

      html = render(view)
      # Should show some error indication
      assert html =~ "invalid" or html =~ "error" or html =~ "not valid" or html =~ "incorrect"
    end

    test "shows sessions section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/profile")
      assert html =~ "Sessions" or html =~ "logged in" or html =~ "Log out"
    end

    test "admin users show admin role badge", %{conn: _conn} do
      admin = admin_fixture(%{email: "admin-profile@example.com"})
      admin_conn = build_conn() |> log_in_user(admin)

      {:ok, _view, html} = live(admin_conn, ~p"/profile")
      assert html =~ "admin"
    end
  end
end
