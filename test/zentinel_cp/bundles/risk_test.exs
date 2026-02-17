defmodule ZentinelCp.Bundles.RiskTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Bundles.Risk

  describe "score/2" do
    test "returns low risk when no previous config" do
      config = """
      route "/api" {
        upstream "backend"
      }
      """

      assert {"low", []} = Risk.score(config, nil)
    end

    test "returns low risk when configs are identical" do
      config = """
      route "/api" {
        upstream "backend"
      }
      """

      assert {"low", []} = Risk.score(config, config)
    end

    test "returns high risk when auth policy changes" do
      prev = """
      auth {
        type "bearer"
        required true
      }
      route "/api" {
        upstream "backend"
      }
      """

      new = """
      auth {
        type "basic"
        required false
      }
      route "/api" {
        upstream "backend"
      }
      """

      {level, reasons} = Risk.score(new, prev)
      assert level == "high"
      assert "auth_policy_changed" in reasons
    end

    test "returns high risk when TLS config changes" do
      prev = """
      tls {
        cert "/etc/ssl/cert.pem"
        key "/etc/ssl/key.pem"
      }
      """

      new = """
      tls {
        cert "/etc/ssl/new-cert.pem"
        key "/etc/ssl/new-key.pem"
      }
      """

      {level, reasons} = Risk.score(new, prev)
      assert level == "high"
      assert "tls_config_changed" in reasons
    end

    test "returns medium risk when many routes change" do
      prev_routes =
        for i <- 1..5 do
          "route \"/path-#{i}\" {\n  upstream \"backend\"\n}"
        end
        |> Enum.join("\n")

      new_routes =
        for i <- 1..20 do
          "route \"/path-#{i}\" {\n  upstream \"backend\"\n}"
        end
        |> Enum.join("\n")

      {level, reasons} = Risk.score(new_routes, prev_routes)
      assert level == "medium"
      assert "many_route_changes" in reasons
    end

    test "returns medium risk when upstream is removed" do
      prev = """
      upstream "backend" {
        host "10.0.0.1"
      }
      upstream "legacy" {
        host "10.0.0.2"
      }
      """

      new = """
      upstream "backend" {
        host "10.0.0.1"
      }
      """

      {level, reasons} = Risk.score(new, prev)
      assert level == "medium"
      assert "upstream_removed" in reasons
    end

    test "returns medium risk when rate limit changes" do
      prev = """
      rate_limit {
        requests 100
        window "1m"
      }
      """

      new = """
      rate_limit {
        requests 1000
        window "1m"
      }
      """

      {level, reasons} = Risk.score(new, prev)
      assert level == "medium"
      assert "rate_limit_changed" in reasons
    end

    test "accumulates multiple risk reasons" do
      prev = """
      auth {
        type "bearer"
      }
      upstream "backend" {
        host "10.0.0.1"
      }
      upstream "legacy" {
        host "10.0.0.2"
      }
      """

      new = """
      auth {
        type "basic"
      }
      upstream "backend" {
        host "10.0.0.1"
      }
      """

      {level, reasons} = Risk.score(new, prev)
      assert level == "high"
      assert "auth_policy_changed" in reasons
      assert "upstream_removed" in reasons
    end

    test "does not flag auth change when no previous auth block" do
      new = """
      auth {
        type "bearer"
      }
      """

      {level, reasons} = Risk.score(new, "route \"/\" {}")
      assert level == "low"
      refute "auth_policy_changed" in reasons
    end
  end
end
