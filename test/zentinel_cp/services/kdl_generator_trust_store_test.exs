defmodule ZentinelCp.Services.KdlGeneratorTrustStoreTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services.{KdlGenerator, ProjectConfig, Service, UpstreamGroup, TrustStore}

  defp default_config do
    %ProjectConfig{
      log_level: "info",
      metrics_port: 9090,
      custom_settings: %{},
      default_cors: %{},
      default_compression: %{},
      global_access_control: %{}
    }
  end

  defp test_service(upstream_group_id) do
    %Service{
      name: "API",
      slug: "api",
      route_path: "/api/*",
      upstream_url: nil,
      upstream_group_id: upstream_group_id,
      retry: %{},
      cache: %{},
      rate_limit: %{},
      health_check: %{},
      headers: %{}
    }
  end

  describe "trust store KDL generation" do
    test "generates trust_stores block for used trust stores" do
      ts_id = Ecto.UUID.generate()
      group_id = Ecto.UUID.generate()

      trust_store = %TrustStore{
        id: ts_id,
        name: "Internal CA",
        slug: "internal-ca",
        certificates_pem: "---pem---",
        cert_count: 1,
        subjects: ["internal.example.com"]
      }

      group = %UpstreamGroup{
        id: group_id,
        name: "API Backends",
        slug: "api-backends",
        algorithm: "round_robin",
        targets: [],
        trust_store_id: ts_id,
        health_check: %{},
        circuit_breaker: %{},
        sticky_sessions: %{}
      }

      services = [test_service(group_id)]

      kdl =
        KdlGenerator.build_kdl(services, default_config(), [group], [], [], %{}, [trust_store])

      assert kdl =~ "trust_stores {"
      assert kdl =~ ~s(store "internal-ca")
      assert kdl =~ ~s(ca_file "/etc/zentinel/trust-stores/internal-ca.pem")
    end

    test "generates tls verify block in upstream group" do
      ts_id = Ecto.UUID.generate()
      group_id = Ecto.UUID.generate()

      trust_store = %TrustStore{
        id: ts_id,
        name: "Internal CA",
        slug: "internal-ca",
        certificates_pem: "---pem---",
        cert_count: 1,
        subjects: ["internal.example.com"]
      }

      group = %UpstreamGroup{
        id: group_id,
        name: "API Backends",
        slug: "api-backends",
        algorithm: "round_robin",
        targets: [],
        trust_store_id: ts_id,
        health_check: %{},
        circuit_breaker: %{},
        sticky_sessions: %{}
      }

      services = [test_service(group_id)]

      kdl =
        KdlGenerator.build_kdl(services, default_config(), [group], [], [], %{}, [trust_store])

      assert kdl =~ "tls {"
      assert kdl =~ "verify true"
      assert kdl =~ ~s(ca_file "/etc/zentinel/trust-stores/internal-ca.pem")
    end

    test "does not generate trust_stores block when no trust stores used" do
      group_id = Ecto.UUID.generate()

      group = %UpstreamGroup{
        id: group_id,
        name: "API Backends",
        slug: "api-backends",
        algorithm: "round_robin",
        targets: [],
        trust_store_id: nil,
        health_check: %{},
        circuit_breaker: %{},
        sticky_sessions: %{}
      }

      services = [test_service(group_id)]

      kdl = KdlGenerator.build_kdl(services, default_config(), [group], [], [], %{}, [])

      refute kdl =~ "trust_stores {"
    end

    test "does not generate tls block for upstream group without trust store" do
      group_id = Ecto.UUID.generate()

      group = %UpstreamGroup{
        id: group_id,
        name: "API Backends",
        slug: "api-backends",
        algorithm: "round_robin",
        targets: [],
        trust_store_id: nil,
        health_check: %{},
        circuit_breaker: %{},
        sticky_sessions: %{}
      }

      services = [test_service(group_id)]

      kdl = KdlGenerator.build_kdl(services, default_config(), [group], [], [], %{}, [])

      refute kdl =~ "verify true"
    end
  end
end
