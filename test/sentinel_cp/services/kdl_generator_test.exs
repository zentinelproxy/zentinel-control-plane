defmodule SentinelCp.Services.KdlGeneratorTest do
  use SentinelCp.DataCase

  alias SentinelCp.Services.{KdlGenerator, ProjectConfig, Service, Certificate, AuthPolicy}

  import SentinelCp.ProjectsFixtures
  import SentinelCp.ServicesFixtures

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

  describe "build_kdl/2" do
    test "generates settings block" do
      config = %ProjectConfig{
        log_level: "debug",
        metrics_port: 9191,
        custom_settings: %{},
        default_cors: %{},
        default_compression: %{},
        global_access_control: %{}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://localhost:3000",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ ~s(log_level "debug")
      assert kdl =~ "metrics_port 9191"
    end

    test "generates route with upstream" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          timeout_seconds: 30,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ ~s(route "/api/*")
      assert kdl =~ ~s(upstream "http://api:8080")
      assert kdl =~ "timeout 30s"
    end

    test "generates route with static response" do
      services = [
        %Service{
          name: "Health",
          slug: "health",
          route_path: "/health",
          upstream_url: nil,
          respond_status: 200,
          respond_body: "OK",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ ~s(route "/health")
      assert kdl =~ ~s(respond 200 "OK")
    end

    test "generates retry block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{"attempts" => 3, "backoff" => "exponential"},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "retry {"
      assert kdl =~ "attempts 3"
      assert kdl =~ ~s(backoff "exponential")
    end

    test "generates cache block" do
      services = [
        %Service{
          name: "Static",
          slug: "static",
          route_path: "/static/*",
          upstream_url: "http://cdn:80",
          cache: %{"ttl" => 3600, "vary" => "Accept-Encoding"},
          retry: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "cache {"
      assert kdl =~ "ttl 3600"
      assert kdl =~ ~s(vary "Accept-Encoding")
    end

    test "generates rate_limits block for services with rate limits" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          rate_limit: %{"requests" => 100, "window" => "60s", "by" => "client_ip"},
          retry: %{},
          cache: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "rate_limits {"
      assert kdl =~ ~s(limit "api")
      assert kdl =~ "requests 100"
      assert kdl =~ ~s(window "60s")
      assert kdl =~ ~s(by "client_ip")
    end

    test "does not generate rate_limits block when no services have rate limits" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          rate_limit: %{},
          retry: %{},
          cache: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      refute kdl =~ "rate_limits {"
    end

    test "generates multiple routes ordered by position" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        },
        %Service{
          name: "Health",
          slug: "health",
          route_path: "/health",
          upstream_url: nil,
          respond_status: 200,
          respond_body: "OK",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      api_pos = :binary.match(kdl, "/api/*") |> elem(0)
      health_pos = :binary.match(kdl, "/health") |> elem(0)
      assert api_pos < health_pos
    end

    test "generates cors block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          cors: %{"allowed_origins" => "*", "max_age" => 86400},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "cors {"
      assert kdl =~ ~s(allowed_origins "*")
      assert kdl =~ "max_age 86400"
    end

    test "generates access_control block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          access_control: %{"allow" => "10.0.0.0/8", "mode" => "deny_first"},
          cors: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "access_control {"
      assert kdl =~ ~s(allow "10.0.0.0/8")
      assert kdl =~ ~s(mode "deny_first")
    end

    test "generates compression block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          compression: %{"algorithms" => "gzip, brotli", "min_size" => 1024},
          cors: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          access_control: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "compression {"
      assert kdl =~ ~s(algorithms "gzip, brotli")
      assert kdl =~ "min_size 1024"
    end

    test "generates path_rewrite block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/v1/*",
          upstream_url: "http://api:8080",
          path_rewrite: %{"strip_prefix" => "/api/v1", "add_prefix" => "/v2"},
          cors: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          access_control: %{},
          compression: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "path_rewrite {"
      assert kdl =~ ~s(strip_prefix "/api/v1")
      assert kdl =~ ~s(add_prefix "/v2")
    end

    test "generates redirect route type" do
      services = [
        %Service{
          name: "Old API",
          slug: "old-api",
          route_path: "/old/*",
          upstream_url: nil,
          redirect_url: "https://new.example.com/api",
          respond_status: 301,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ ~s(route "/old/*")
      assert kdl =~ ~s(redirect 301 "https://new.example.com/api")
      refute kdl =~ "upstream"
      refute kdl =~ "respond"
    end

    test "generates global compression in settings" do
      config = %ProjectConfig{
        log_level: "info",
        metrics_port: 9090,
        custom_settings: %{},
        default_cors: %{},
        default_compression: %{"algorithms" => "gzip", "min_size" => 256},
        global_access_control: %{}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      # Global compression should be inside settings block
      assert kdl =~ "settings {"
      assert kdl =~ "compression {"
      assert kdl =~ ~s(algorithms "gzip")
    end

    test "generates global access_control in settings" do
      config = %ProjectConfig{
        log_level: "info",
        metrics_port: 9090,
        custom_settings: %{},
        default_cors: %{},
        default_compression: %{},
        global_access_control: %{"deny" => "0.0.0.0/0", "mode" => "deny_first"}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ "settings {"
      assert kdl =~ "access_control {"
      assert kdl =~ ~s(deny "0.0.0.0/0")
    end

    test "generates tls block for certificates referenced by services" do
      cert = %Certificate{
        id: "cert-1",
        slug: "api-cert",
        domain: "api.example.com",
        san_domains: ["www.example.com", "cdn.example.com"]
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          certificate_id: "cert-1",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [], [cert])

      # Top-level tls block
      assert kdl =~ "tls {"
      assert kdl =~ ~s(certificate "api-cert" {)
      assert kdl =~ ~s(domain "api.example.com")
      assert kdl =~ ~s(cert_file "/etc/sentinel/certs/api-cert.pem")
      assert kdl =~ ~s(key_file "/etc/sentinel/certs/api-cert.key")
      assert kdl =~ ~s(san_domains "www.example.com" "cdn.example.com")

      # Route-level tls reference
      assert kdl =~ "tls {"
      assert kdl =~ ~s(certificate "api-cert")
    end

    test "does not generate tls block when no certificates are used" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          certificate_id: nil,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [], [])
      refute kdl =~ "tls {"
    end

    test "generates tls certificate without SAN when san_domains is empty" do
      cert = %Certificate{
        id: "cert-2",
        slug: "simple-cert",
        domain: "simple.example.com",
        san_domains: []
      }

      services = [
        %Service{
          name: "Simple",
          slug: "simple",
          route_path: "/simple/*",
          upstream_url: "http://simple:8080",
          certificate_id: "cert-2",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [], [cert])
      assert kdl =~ ~s(certificate "simple-cert" {)
      assert kdl =~ ~s(domain "simple.example.com")
      refute kdl =~ "san_domains"
    end

    test "includes custom settings" do
      config = %ProjectConfig{
        log_level: "info",
        metrics_port: 9090,
        custom_settings: %{"max_connections" => 1000},
        default_cors: %{},
        default_compression: %{},
        global_access_control: %{}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ "max_connections 1000"
    end
  end

  describe "security block KDL" do
    test "generates security block for service" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          security: %{
            "block_sqli" => "true",
            "block_xss" => "true",
            "max_body_size" => 1_048_576
          },
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{},
          request_transform: %{},
          response_transform: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "security {"
      assert kdl =~ ~s(block_sqli "true")
      assert kdl =~ ~s(block_xss "true")
      assert kdl =~ "max_body_size 1048576"
    end

    test "does not generate security block when empty" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          security: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      refute kdl =~ "security {"
    end

    test "generates global security in settings" do
      config = %ProjectConfig{
        log_level: "info",
        metrics_port: 9090,
        custom_settings: %{},
        default_cors: %{},
        default_compression: %{},
        global_access_control: %{},
        default_security: %{"max_body_size" => 2_097_152, "block_sqli" => "true"}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{},
          security: %{},
          request_transform: %{},
          response_transform: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, config)
      assert kdl =~ "settings {"
      assert kdl =~ "security {"
      assert kdl =~ "max_body_size 2097152"
    end
  end

  describe "transform block KDL" do
    test "generates request_transform block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          request_transform: %{
            "add_headers" => "X-Custom: value",
            "remove_headers" => "X-Forwarded-For"
          },
          response_transform: %{},
          security: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "request_transform {"
      assert kdl =~ ~s(add_headers "X-Custom: value")
      assert kdl =~ ~s(remove_headers "X-Forwarded-For")
    end

    test "generates response_transform block" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          response_transform: %{
            "add_headers" => "X-Frame-Options: DENY",
            "remove_headers" => "Server"
          },
          request_transform: %{},
          security: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      assert kdl =~ "response_transform {"
      assert kdl =~ ~s(add_headers "X-Frame-Options: DENY")
      assert kdl =~ ~s(remove_headers "Server")
    end

    test "does not generate transform blocks when empty" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          request_transform: %{},
          response_transform: %{},
          security: %{},
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      refute kdl =~ "request_transform {"
      refute kdl =~ "response_transform {"
    end
  end

  describe "auth block KDL" do
    test "generates auth block when service has auth_policy_id" do
      policy = %AuthPolicy{
        id: "policy-1",
        slug: "jwt-validator",
        name: "JWT Validator",
        auth_type: "jwt",
        config: %{
          "audience" => "my-api",
          "issuer" => "https://auth.example.com",
          "jwks_url" => "https://auth.example.com/.well-known/jwks.json"
        },
        enabled: true
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          auth_policy_id: "policy-1",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [], [], [policy])
      assert kdl =~ "auth {"
      assert kdl =~ ~s(type "jwt")
      assert kdl =~ ~s(issuer "https://auth.example.com")
      assert kdl =~ ~s(audience "my-api")
      assert kdl =~ ~s(jwks_url "https://auth.example.com/.well-known/jwks.json")
    end

    test "does not generate auth block when auth_policy_id is nil" do
      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          auth_policy_id: nil,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config())
      refute kdl =~ "auth {"
    end

    test "generates auth block for api_key type" do
      policy = %AuthPolicy{
        id: "policy-2",
        slug: "api-key-check",
        name: "API Key Check",
        auth_type: "api_key",
        config: %{"header" => "X-API-Key", "query_param" => "api_key"},
        enabled: true
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          auth_policy_id: "policy-2",
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [], [], [policy])
      assert kdl =~ "auth {"
      assert kdl =~ ~s(type "api_key")
      assert kdl =~ ~s(header "X-API-Key")
      assert kdl =~ ~s(query_param "api_key")
    end
  end

  describe "circuit_breaker KDL" do
    test "generates circuit_breaker block inside upstream group" do
      group = %SentinelCp.Services.UpstreamGroup{
        id: "group-1",
        slug: "api-backends",
        name: "API Backends",
        algorithm: "round_robin",
        targets: [],
        health_check: %{},
        sticky_sessions: %{},
        circuit_breaker: %{
          "failure_threshold" => 5,
          "success_threshold" => 3,
          "timeout" => 30,
          "half_open_max_requests" => 1
        }
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_group_id: "group-1",
          upstream_url: nil,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [group])
      assert kdl =~ "circuit_breaker {"
      assert kdl =~ "failure_threshold 5"
      assert kdl =~ "success_threshold 3"
      assert kdl =~ "timeout 30"
      assert kdl =~ "half_open_max_requests 1"
    end

    test "does not generate circuit_breaker block when config is empty" do
      group = %SentinelCp.Services.UpstreamGroup{
        id: "group-1",
        slug: "api-backends",
        name: "API Backends",
        algorithm: "round_robin",
        targets: [],
        health_check: %{},
        sticky_sessions: %{},
        circuit_breaker: %{}
      }

      services = [
        %Service{
          name: "API",
          slug: "api",
          route_path: "/api/*",
          upstream_group_id: "group-1",
          upstream_url: nil,
          retry: %{},
          cache: %{},
          rate_limit: %{},
          health_check: %{},
          headers: %{},
          cors: %{},
          access_control: %{},
          compression: %{},
          path_rewrite: %{}
        }
      ]

      kdl = KdlGenerator.build_kdl(services, default_config(), [group])
      refute kdl =~ "circuit_breaker {"
    end
  end

  describe "generate/1" do
    test "returns error when no services exist" do
      project = project_fixture()
      assert {:error, :no_services} = KdlGenerator.generate(project.id)
    end

    test "returns error when all services are disabled" do
      project = project_fixture()
      _s = service_fixture(%{project: project, enabled: false})
      assert {:error, :no_services} = KdlGenerator.generate(project.id)
    end

    test "generates KDL from database services" do
      project = project_fixture()
      _s = service_fixture(%{project: project, name: "API Backend", route_path: "/api/*"})

      assert {:ok, kdl} = KdlGenerator.generate(project.id)
      assert kdl =~ "settings {"
      assert kdl =~ "routes {"
      assert kdl =~ ~s(route "/api/*")
    end
  end
end
