defmodule ZentinelCpWeb.E2E.LoginFlowTest do
  @moduledoc """
  E2E tests for user login flows.

  Tests valid login, invalid credentials, and redirect to login.
  """
  use ZentinelCpWeb.FeatureCase

  @moduletag :e2e

  import Wallaby.Query

  describe "login flow" do
    feature "valid login redirects away from login page", %{session: session} do
      user =
        ZentinelCp.AccountsFixtures.user_fixture(%{
          email: "test@example.com",
          password: "SecurePassword123!"
        })

      session
      |> visit("/login")
      |> assert_has(css("h1", text: "Sign in"))
      |> fill_in(text_field("Email"), with: user.email)
      |> fill_in(css("input[type='password']"), with: "SecurePassword123!")
      |> click(button("Sign in"))
      # After login, user is redirected away from login page
      |> refute_has(css("h1", text: "Sign in"))
    end

    feature "invalid email shows error", %{session: session} do
      session
      |> visit("/login")
      |> fill_in(text_field("Email"), with: "nonexistent@example.com")
      |> fill_in(css("input[type='password']"), with: "SomePassword123!")
      |> click(button("Sign in"))
      # Flash error appears with alert-error class
      |> assert_has(css(".alert-error", text: "Invalid"))
    end

    feature "invalid password shows error", %{session: session} do
      user = ZentinelCp.AccountsFixtures.user_fixture()

      session
      |> visit("/login")
      |> fill_in(text_field("Email"), with: user.email)
      |> fill_in(css("input[type='password']"), with: "WrongPassword123!")
      |> click(button("Sign in"))
      |> assert_has(css(".alert-error", text: "Invalid"))
    end

    feature "form has required fields", %{session: session} do
      # This test verifies the form has email and password inputs with required attribute
      session
      |> visit("/login")
      |> assert_has(css("input[type='email'][required]"))
      |> assert_has(css("input[type='password'][required]"))
    end
  end

  describe "redirect to login" do
    feature "unauthenticated user redirected to login", %{session: session} do
      org = ZentinelCp.OrgsFixtures.org_fixture()

      session
      |> visit("/orgs/#{org.slug}/dashboard")
      |> assert_has(css("h1", text: "Sign in"))
    end

    feature "protected routes require authentication", %{session: session} do
      session
      |> visit("/audit")
      |> assert_has(css("h1", text: "Sign in"))
    end
  end

  describe "authenticated navigation" do
    feature "logged in user has navigation", %{session: session} do
      {session, _user} = create_and_login_user(session)

      # After login, user should see the main navigation
      session
      |> assert_has(css("nav"))
    end
  end
end
