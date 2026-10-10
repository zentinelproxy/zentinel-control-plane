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
  Visits a LiveView page and waits until its socket has joined.

  The first response is a static render. Until the LiveView connects,
  `phx-click`, `phx-change` and `phx-submit` do nothing, so a test that
  interacts straight after `visit/2` loses the event whenever the join is
  slower than the test (as on CI runners).
  """
  def visit_live(session, path) do
    import Wallaby.Browser
    import Wallaby.Query

    session
    |> visit(path)
    |> assert_has(css("[data-phx-main].phx-connected"))
  end

  @doc """
  Logs in a user via the browser login form.
  Returns the session after successful login.
  """
  def log_in_via_browser(session, email, password) do
    import Wallaby.Browser
    import Wallaby.Query

    session
    |> visit_live("/login")
    |> fill_in(text_field("Email"), with: email)
    |> fill_in(text_field("Password"), with: password)
    |> click(button("Sign in"))
    |> wait_for_navigation_from("/login")
  end

  @doc """
  Waits until the browser has navigated away from `path`.

  Polls the URL rather than querying the old page: elements of a document that
  is being replaced raise a non-retried "Node ... does not belong to the
  document" error from ChromeDriver.
  """
  def wait_for_navigation_from(session, path) do
    timeout = Application.get_env(:wallaby, :max_wait_time, 5_000)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_navigation_from(session, path, deadline)
  end

  defp do_wait_for_navigation_from(session, path, deadline) do
    cond do
      Wallaby.Browser.current_path(session) != path ->
        session

      System.monotonic_time(:millisecond) > deadline ->
        raise "still on #{path} after waiting for navigation"

      true ->
        Process.sleep(50)
        do_wait_for_navigation_from(session, path, deadline)
    end
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
