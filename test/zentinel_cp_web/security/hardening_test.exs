defmodule ZentinelCpWeb.Security.HardeningTest do
  use ZentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ZentinelCp.AccountsFixtures

  alias ZentinelCp.Accounts.Totp
  alias ZentinelCp.Net.UrlGuard
  alias ZentinelCp.Orgs
  alias ZentinelCp.RateLimit

  defp put_env(key, value) do
    original = Application.fetch_env(:zentinel_cp, key)
    Application.put_env(:zentinel_cp, key, value)

    on_exit(fn ->
      case original do
        {:ok, previous} -> Application.put_env(:zentinel_cp, key, previous)
        :error -> Application.delete_env(:zentinel_cp, key)
      end
    end)
  end

  defp enrolled_user do
    user = user_fixture()
    {:ok, totp} = Totp.create_user_totp(user.id)
    {:ok, totp} = Totp.verify_totp_enrollment(totp, NimbleTOTP.verification_code(totp.secret))

    # Clear the enrollment use so the same time step's code can be used to log in.
    totp =
      totp |> Ecto.Changeset.change(last_used_at: nil) |> ZentinelCp.Repo.update!()

    {user, totp}
  end

  defp sign_in(conn, user) do
    post(conn, "/session", %{"email" => user.email, "password" => valid_user_password()})
  end

  describe "MFA login" do
    test "a password alone does not sign in an enrolled user", %{conn: conn} do
      {user, _totp} = enrolled_user()
      conn = sign_in(conn, user)

      assert redirected_to(conn) == "/login/mfa"
      refute get_session(conn, :user_token)
    end

    test "a valid code completes the login", %{conn: conn} do
      {user, totp} = enrolled_user()
      conn = sign_in(conn, user)
      conn = post(conn, "/session/mfa", %{"code" => NimbleTOTP.verification_code(totp.secret)})

      assert get_session(conn, :user_token)
      refute get_session(conn, :mfa_user_id)
    end

    test "a wrong code does not", %{conn: conn} do
      {user, _totp} = enrolled_user()
      conn = sign_in(conn, user)
      conn = post(conn, "/session/mfa", %{"code" => "000000"})

      assert redirected_to(conn) == "/login/mfa"
      refute get_session(conn, :user_token)
    end

    test "a code without a password step does nothing", %{conn: conn} do
      {_user, totp} = enrolled_user()

      conn =
        conn
        |> init_test_session(%{})
        |> post("/session/mfa", %{"code" => NimbleTOTP.verification_code(totp.secret)})

      assert redirected_to(conn) == "/login"
      refute get_session(conn, :user_token)
    end

    test "an unenrolled user signs in with a password", %{conn: conn} do
      conn = sign_in(conn, user_fixture())
      assert get_session(conn, :user_token)
    end
  end

  describe "MFA enrollment" do
    test "a user enrolls from their profile", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/profile")

      assert view |> element("button", "Set up") |> render_click() =~ "recovery codes"

      totp = Totp.get_user_totp(user.id)
      code = NimbleTOTP.verification_code(totp.secret)

      assert render_submit(view, "confirm_mfa", %{"code" => code}) =~
               "Two-factor authentication is on"

      assert Totp.mfa_enabled?(user.id)
    end
  end

  describe "org MFA policy" do
    test "blocks an unenrolled member once required", %{conn: conn} do
      org = ZentinelCp.OrgsFixtures.org_fixture()
      project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: org})
      user = user_fixture()
      {:ok, _} = Orgs.add_member(org, user, "operator")

      {:ok, _} = Orgs.update_org(org, %{settings: %{"mfa_policy" => "required"}})

      assert {:error, {:redirect, %{to: "/profile"}}} =
               conn |> log_in_user(user) |> live("/projects/#{project.slug}/nodes")
    end

    test "lets a member in during the grace period", %{conn: conn} do
      org = ZentinelCp.OrgsFixtures.org_fixture()
      project = ZentinelCp.ProjectsFixtures.project_fixture(%{org: org})
      user = user_fixture()
      {:ok, _} = Orgs.add_member(org, user, "operator")

      {:ok, _} =
        Orgs.update_org(org, %{
          settings: %{
            "mfa_policy" => "required",
            "mfa_enforced_at" => DateTime.to_iso8601(DateTime.utc_now())
          }
        })

      assert {:ok, _, _} = conn |> log_in_user(user) |> live("/projects/#{project.slug}/nodes")
    end
  end

  describe "rate limits" do
    test "login attempts are limited per address", %{conn: conn} do
      put_env(:rate_limits, %{"login" => 2})
      RateLimit.reset_all()
      on_exit(&RateLimit.reset_all/0)
      params = %{"email" => "nobody@example.com", "password" => "wrong"}

      assert post(conn, "/session", params).status == 302
      assert post(conn, "/session", params).status == 302
      assert post(conn, "/session", params).status == 429
    end

    test "API limits follow the key, not the address", %{conn: conn} do
      project = ZentinelCp.ProjectsFixtures.project_fixture()
      {conn, _} = authenticate_api(conn, project: project)
      assert conn |> get("/api/v1/projects/#{project.slug}/nodes") |> json_response(200)

      {_, key} = authenticate_api(build_conn(), project: project)
      assert RateLimit.current_usage("api_key:#{key.id}", "default") == 0
    end
  end

  describe "client address" do
    test "a forged X-Forwarded-For is ignored by default", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-forwarded-for", "1.2.3.4")
        |> get("/health")

      assert conn.remote_ip == {127, 0, 0, 1}
    end

    test "the proxy's entry is used, not a client's forgery", %{conn: conn} do
      put_env(:trusted_proxy_count, 1)

      conn =
        conn
        |> put_req_header("x-forwarded-for", "1.2.3.4, 9.9.9.9")
        |> get("/health")

      assert conn.remote_ip == {9, 9, 9, 9}
    end
  end

  describe "/metrics" do
    test "is closed without a configured token", %{conn: conn} do
      put_env(:metrics_open, false)
      put_env(:metrics_token, nil)
      assert get(conn, "/metrics").status == 401
    end

    test "requires the token", %{conn: conn} do
      put_env(:metrics_open, false)
      put_env(:metrics_token, "s3cret")

      assert get(conn, "/metrics").status == 401

      assert conn
             |> put_req_header("authorization", "Bearer s3cret")
             |> get("/metrics")
             |> Map.fetch!(:status) == 200
    end
  end

  describe "transport and browser headers" do
    test "FORCE_SSL redirects at runtime but not health checks", %{conn: conn} do
      put_env(:force_ssl, true)

      assert get(conn, "/login").status == 301
      assert get(conn, "/health").status == 200
    end

    test "session cookies are secure when FORCE_SSL is on" do
      put_env(:force_ssl, true)

      conn =
        build_conn(:post, "https://www.example.com/session", %{
          "email" => "x@example.com",
          "password" => "y"
        })
        |> ZentinelCpWeb.Endpoint.call([])

      assert %{secure: true} = conn.resp_cookies["_zentinel_cp_key"]
    end

    test "templates have no inline handlers, which the CSP would block" do
      offenders =
        for path <- Path.wildcard("lib/zentinel_cp_web/**/*.{ex,heex}"),
            not String.ends_with?(path, "api_docs_controller.ex"),
            Regex.match?(~r/\son(click|change|submit|load|input|keyup)=/, File.read!(path)),
            do: path

      assert offenders == []
    end

    test "pages send a CSP whose nonce matches the inline script", %{conn: conn} do
      conn = get(conn, "/login")
      [policy] = get_resp_header(conn, "content-security-policy")
      [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, policy)

      assert policy =~ "frame-ancestors 'none'"
      assert html_response(conn, 200) =~ ~s(nonce="#{nonce}")
    end
  end

  describe "UrlGuard" do
    setup do
      put_env(:allow_private_outbound, false)
    end

    test "blocks cloud metadata and loopback under both policies" do
      for url <- ["http://169.254.169.254/latest", "http://127.0.0.1/", "http://[::1]/"],
          policy <- [:public, :no_local] do
        assert {:error, :forbidden_address} = UrlGuard.check(url, policy)
      end
    end

    test "blocks an IPv4-mapped IPv6 metadata address" do
      assert {:error, :forbidden_address} = UrlGuard.check("http://[::ffff:169.254.169.254]/")
    end

    test "private networks depend on the policy" do
      assert {:error, :forbidden_address} = UrlGuard.check("http://10.0.0.5/", :public)
      assert :ok = UrlGuard.check("http://10.0.0.5/", :no_local)
    end

    test "allows public addresses" do
      assert :ok = UrlGuard.check("https://1.1.1.1/hook", :public)
    end

    test "rejects other schemes" do
      assert {:error, :invalid_url} = UrlGuard.check("file:///etc/passwd")
      assert {:error, :invalid_url} = UrlGuard.check("gopher://1.1.1.1/")
    end

    test "webhook delivery refuses a forbidden address" do
      assert {:error, :forbidden_address} =
               ZentinelCp.Events.Adapters.Webhook.deliver("http://169.254.169.254/", %{})
    end
  end
end
