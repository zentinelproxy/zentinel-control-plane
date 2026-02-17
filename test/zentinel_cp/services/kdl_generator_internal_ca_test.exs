defmodule ZentinelCp.Services.KdlGeneratorInternalCaTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Services.KdlGenerator
  alias ZentinelCp.Services.{ProjectConfig, InternalCa, AuthPolicy}

  @default_config %ProjectConfig{
    log_level: "info",
    metrics_port: 9090,
    custom_settings: %{},
    default_compression: %{},
    global_access_control: %{},
    default_security: %{}
  }

  defp make_service(opts \\ %{}) do
    %ZentinelCp.Services.Service{
      id: opts[:id] || Ecto.UUID.generate(),
      slug: opts[:slug] || "test-svc",
      route_path: opts[:route_path] || "/api",
      upstream_url: opts[:upstream_url] || "http://localhost:8080",
      enabled: true,
      service_type: "standard",
      timeout_seconds: nil,
      retry: %{},
      cache: %{},
      health_check: %{},
      headers: %{},
      cors: %{},
      access_control: %{},
      compression: %{},
      path_rewrite: %{},
      certificate_id: nil,
      auth_policy_id: opts[:auth_policy_id],
      security: %{},
      request_transform: %{},
      response_transform: %{},
      traffic_split: %{},
      inference: %{},
      grpc: %{},
      websocket: %{},
      graphql: %{},
      streaming: %{},
      redirect_url: nil,
      respond_status: nil,
      respond_body: nil,
      upstream_group_id: nil,
      rate_limit: %{}
    }
  end

  describe "client_auth block" do
    test "includes client_auth block when internal CA exists" do
      internal_ca = %InternalCa{
        id: Ecto.UUID.generate(),
        name: "Test CA",
        slug: "test-ca",
        subject_cn: "Test CA",
        key_algorithm: "EC-P384",
        status: "active"
      }

      service = make_service()

      kdl =
        KdlGenerator.build_kdl(
          [service],
          @default_config,
          [],
          [],
          [],
          %{},
          [],
          internal_ca
        )

      assert kdl =~ "client_auth {"
      assert kdl =~ ~s(ca_file "/etc/zentinel/internal-ca/ca.pem")
      assert kdl =~ ~s(crl_file "/etc/zentinel/internal-ca/crl.pem")
    end

    test "does not include client_auth block when no internal CA" do
      service = make_service()

      kdl =
        KdlGenerator.build_kdl(
          [service],
          @default_config,
          [],
          [],
          [],
          %{},
          [],
          nil
        )

      refute kdl =~ "client_auth"
    end
  end

  describe "mTLS auth block" do
    test "generates mTLS auth block with CA file paths" do
      policy_id = Ecto.UUID.generate()

      policy = %AuthPolicy{
        id: policy_id,
        auth_type: "mtls",
        config: %{"verify_mode" => "optional"}
      }

      internal_ca = %InternalCa{
        id: Ecto.UUID.generate(),
        name: "Test CA",
        slug: "test-ca",
        subject_cn: "Test CA",
        key_algorithm: "EC-P384",
        status: "active"
      }

      service = make_service(%{auth_policy_id: policy_id})

      kdl =
        KdlGenerator.build_kdl(
          [service],
          @default_config,
          [],
          [],
          [policy],
          %{},
          [],
          internal_ca
        )

      assert kdl =~ ~s(type "mtls")
      assert kdl =~ ~s(verify_mode "optional")
      assert kdl =~ ~s(ca_file "/etc/zentinel/internal-ca/ca.pem")
      assert kdl =~ ~s(crl_file "/etc/zentinel/internal-ca/crl.pem")
    end

    test "mTLS auth block uses default verify_mode require" do
      policy_id = Ecto.UUID.generate()

      policy = %AuthPolicy{
        id: policy_id,
        auth_type: "mtls",
        config: %{}
      }

      internal_ca = %InternalCa{
        id: Ecto.UUID.generate(),
        name: "Test CA",
        slug: "test-ca",
        subject_cn: "Test CA",
        key_algorithm: "EC-P384",
        status: "active"
      }

      service = make_service(%{auth_policy_id: policy_id})

      kdl =
        KdlGenerator.build_kdl(
          [service],
          @default_config,
          [],
          [],
          [policy],
          %{},
          [],
          internal_ca
        )

      assert kdl =~ ~s(verify_mode "require")
    end

    test "mTLS policy without internal CA falls back to generic auth block" do
      policy_id = Ecto.UUID.generate()

      policy = %AuthPolicy{
        id: policy_id,
        auth_type: "mtls",
        config: %{"verify_mode" => "require"}
      }

      service = make_service(%{auth_policy_id: policy_id})

      kdl =
        KdlGenerator.build_kdl(
          [service],
          @default_config,
          [],
          [],
          [policy],
          %{},
          [],
          nil
        )

      # Without internal CA, it falls back to generic rendering
      assert kdl =~ ~s(type "mtls")
      assert kdl =~ ~s(verify_mode "require")
      refute kdl =~ "ca_file"
    end
  end
end
