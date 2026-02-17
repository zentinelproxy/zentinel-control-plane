defmodule ZentinelCpWeb.HealthControllerTest do
  use ZentinelCpWeb.ConnCase

  describe "GET /health" do
    test "returns 200 ok", %{conn: conn} do
      conn = get(conn, "/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "GET /ready" do
    test "returns 200 when database is available", %{conn: conn} do
      conn = get(conn, "/ready")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end
end
