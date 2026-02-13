defmodule SentinelCpWeb.Api.AcmeChallengeControllerTest do
  use SentinelCpWeb.ConnCase, async: false

  alias SentinelCp.Services.Acme.ChallengeStore

  setup do
    :ets.delete_all_objects(:acme_challenge_tokens)
    :ok
  end

  describe "GET /.well-known/acme-challenge/:token" do
    test "returns 200 with key authorization when token exists", %{conn: conn} do
      ChallengeStore.put("test-token-123", "key-auth-value.thumbprint")

      conn = get(conn, "/.well-known/acme-challenge/test-token-123")

      assert response(conn, 200) == "key-auth-value.thumbprint"
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    end

    test "returns 404 when token does not exist", %{conn: conn} do
      conn = get(conn, "/.well-known/acme-challenge/nonexistent-token")

      assert response(conn, 404) == "Challenge not found"
    end

    test "returns 404 for expired token", %{conn: conn} do
      # Insert with already-expired timestamp
      :ets.insert(:acme_challenge_tokens, {"expired-token", "value", 0})

      conn = get(conn, "/.well-known/acme-challenge/expired-token")

      assert response(conn, 404) == "Challenge not found"
    end
  end
end
