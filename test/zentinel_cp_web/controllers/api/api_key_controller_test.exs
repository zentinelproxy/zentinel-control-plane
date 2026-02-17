defmodule ZentinelCpWeb.Api.ApiKeyControllerTest do
  use ZentinelCpWeb.ConnCase

  alias ZentinelCp.AccountsFixtures
  alias ZentinelCp.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture()

    {conn, api_key} =
      authenticate_api(conn, user: user, project: project, scopes: ["api_keys:admin"])

    %{conn: conn, user: user, project: project, api_key: api_key}
  end

  describe "POST /api/v1/api-keys" do
    test "creates a new API key and returns raw key", %{conn: conn, project: project} do
      params = %{
        "name" => "deploy-key",
        "scopes" => ["bundles:write", "rollouts:write"],
        "project_id" => project.id
      }

      conn = post(conn, "/api/v1/api-keys", params)
      response = json_response(conn, 201)

      assert response["name"] == "deploy-key"
      assert response["key"] != nil
      assert is_binary(response["key"])
      assert response["scopes"] == ["bundles:write", "rollouts:write"]
      assert response["project_id"] == project.id
    end

    test "returns 422 with missing name", %{conn: conn} do
      conn = post(conn, "/api/v1/api-keys", %{"scopes" => ["read"]})
      assert json_response(conn, 422)["error"]
    end
  end

  describe "GET /api/v1/api-keys" do
    test "lists API keys for current user", %{conn: conn} do
      conn = get(conn, "/api/v1/api-keys")
      response = json_response(conn, 200)

      assert is_list(response["api_keys"])
      assert response["total"] >= 1
    end
  end

  describe "GET /api/v1/api-keys/:id" do
    test "shows API key details", %{conn: conn, api_key: api_key} do
      conn = get(conn, "/api/v1/api-keys/#{api_key.id}")
      response = json_response(conn, 200)

      assert response["api_key"]["id"] == api_key.id
      assert response["api_key"]["name"] == api_key.name
      # Raw key should not be included
      refute Map.has_key?(response["api_key"], "key")
    end

    test "returns 404 for nonexistent key", %{conn: conn} do
      conn = get(conn, "/api/v1/api-keys/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"]
    end

    test "returns 404 for another user's key", %{conn: conn} do
      other_user = AccountsFixtures.user_fixture()
      other_key = AccountsFixtures.api_key_fixture(user: other_user)

      conn = get(conn, "/api/v1/api-keys/#{other_key.id}")
      assert json_response(conn, 404)["error"]
    end
  end

  describe "POST /api/v1/api-keys/:id/revoke" do
    test "revokes an API key", %{conn: conn, user: user} do
      target_key = AccountsFixtures.api_key_fixture(user: user)

      conn = post(conn, "/api/v1/api-keys/#{target_key.id}/revoke")
      response = json_response(conn, 200)

      assert response["api_key"]["revoked_at"] != nil
    end

    test "returns 404 for another user's key", %{conn: conn} do
      other_user = AccountsFixtures.user_fixture()
      other_key = AccountsFixtures.api_key_fixture(user: other_user)

      conn = post(conn, "/api/v1/api-keys/#{other_key.id}/revoke")
      assert json_response(conn, 404)["error"]
    end
  end

  describe "DELETE /api/v1/api-keys/:id" do
    test "deletes an API key", %{conn: conn, user: user} do
      target_key = AccountsFixtures.api_key_fixture(user: user)

      conn = delete(conn, "/api/v1/api-keys/#{target_key.id}")
      assert response(conn, 204)
    end

    test "returns 404 for nonexistent key", %{conn: conn} do
      conn = delete(conn, "/api/v1/api-keys/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"]
    end
  end

  describe "scope enforcement" do
    test "returns 403 without api_keys:admin scope", %{conn: _conn} do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture()

      # Authenticate with a key that only has bundles:read
      {conn, _api_key} =
        authenticate_api(Phoenix.ConnTest.build_conn(),
          user: user,
          project: project,
          scopes: ["bundles:read"]
        )

      conn = get(conn, "/api/v1/api-keys")
      assert json_response(conn, 403)["error"] =~ "Insufficient scope"
    end
  end
end
