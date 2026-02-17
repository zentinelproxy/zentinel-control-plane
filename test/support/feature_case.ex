defmodule ZentinelCpWeb.FeatureCase do
  @moduledoc """
  This module defines the test case for browser-based E2E tests using Wallaby.

  These tests run against a real browser (Chrome via ChromeDriver) and verify
  end-to-end user flows including JavaScript interactions and LiveView updates.

  ## Usage

      use ZentinelCpWeb.FeatureCase

      @tag :e2e
      feature "user can log in", %{session: session} do
        session
        |> visit("/login")
        |> fill_in(Query.text_field("Email"), with: "test@example.com")
        |> fill_in(Query.text_field("Password"), with: "password123")
        |> click(Query.button("Log in"))
        |> assert_has(Query.text("Dashboard"))
      end

  ## Requirements

  - ChromeDriver must be installed and running
  - Run with: `mix test.e2e` or `mix test --include e2e`

  ## Configuration

  See `config/test.exs` for Wallaby configuration options.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import Wallaby.Query
      import ZentinelCpWeb.FeatureCase

      alias ZentinelCpWeb.Router.Helpers, as: Routes

      @endpoint ZentinelCpWeb.Endpoint
    end
  end

  setup tags do
    # Note: Do NOT call Ecto.Adapters.SQL.Sandbox.checkout here!
    # Wallaby.Feature handles sandbox checkout automatically via checkout_ecto_repos/2.
    # Calling it manually causes {:already, :owner} errors.

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(ZentinelCp.Repo, {:shared, self()})
    end

    # Pass sandbox metadata to Wallaby so browser requests share the same DB transaction
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(ZentinelCp.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end

  @doc """
  Logs in a user via the browser login form.
  Returns the session after successful login.
  """
  def log_in_via_browser(session, email, password) do
    import Wallaby.Query

    session =
      session
      |> Wallaby.Browser.visit("/login")
      |> Wallaby.Browser.fill_in(text_field("Email"), with: email)
      |> Wallaby.Browser.fill_in(text_field("Password"), with: password)
      |> Wallaby.Browser.click(button("Sign in"))

    # Wait for redirect to complete - page should no longer have the login form
    Process.sleep(1000)
    session
  end

  @doc """
  Creates a user and logs them in via the browser.
  Returns {session, user}.
  """
  def create_and_login_user(session, attrs \\ %{}) do
    user = ZentinelCp.AccountsFixtures.user_fixture(attrs)
    password = attrs[:password] || ZentinelCp.AccountsFixtures.valid_user_password()

    session = log_in_via_browser(session, user.email, password)

    {session, user}
  end

  @doc """
  Creates a full test context with org, project, and logged-in user.
  Returns {session, %{user: user, org: org, project: project}}.
  """
  def setup_full_context(session, attrs \\ %{}) do
    {org, user} = ZentinelCp.OrgsFixtures.org_with_owner_fixture(attrs)
    project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: org})

    password = attrs[:password] || ZentinelCp.AccountsFixtures.valid_user_password()
    session = log_in_via_browser(session, user.email, password)

    {session, %{user: user, org: org, project: project}}
  end
end
