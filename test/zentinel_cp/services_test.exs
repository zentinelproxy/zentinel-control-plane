defmodule ZentinelCp.ServicesTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services
  alias ZentinelCp.Services.{Service, ProjectConfig}

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.AuthPolicyFixtures

  describe "create_service/1" do
    test "creates a service with valid attributes" do
      project = project_fixture()

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "API Backend",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000"
               })

      assert service.name == "API Backend"
      assert service.slug == "api-backend"
      assert service.route_path == "/api/*"
      assert service.upstream_url == "http://localhost:3000"
      assert service.enabled == true
    end

    test "auto-generates slug from name" do
      project = project_fixture()

      {:ok, service} =
        Services.create_service(%{
          project_id: project.id,
          name: "My Cool Service!",
          route_path: "/cool/*",
          upstream_url: "http://cool:8080"
        })

      assert service.slug == "my-cool-service"
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Services.create_service(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:route_path]
      assert errors[:project_id]
    end

    test "returns error when route_path doesn't start with /" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad Route",
                 route_path: "api/*",
                 upstream_url: "http://localhost:3000"
               })

      assert %{route_path: ["must start with /"]} = errors_on(changeset)
    end

    test "returns error when both upstream_url and respond_status are set" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Both Set",
                 route_path: "/both",
                 upstream_url: "http://localhost:3000",
                 respond_status: 200
               })

      assert %{upstream_url: [msg]} = errors_on(changeset)
      assert msg =~ "must set exactly one"
    end

    test "returns error when neither upstream_url nor respond_status is set" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Neither Set",
                 route_path: "/neither"
               })

      assert %{upstream_url: [msg]} = errors_on(changeset)
      assert msg =~ "must set either"
    end

    test "creates a redirect service" do
      project = project_fixture()

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Old API",
                 route_path: "/old-api/*",
                 redirect_url: "https://new-api.example.com"
               })

      assert service.redirect_url == "https://new-api.example.com"
      assert is_nil(service.upstream_url)
      assert is_nil(service.respond_status)
    end

    test "returns error when both upstream_url and redirect_url are set" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Both Set",
                 route_path: "/both",
                 upstream_url: "http://localhost:3000",
                 redirect_url: "https://example.com"
               })

      assert %{upstream_url: [msg]} = errors_on(changeset)
      assert msg =~ "must set exactly one"
    end

    test "creates service with CORS config" do
      project = project_fixture()

      cors = %{"allowed_origins" => "*", "allowed_methods" => "GET, POST", "max_age" => 86400}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "CORS Service",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 cors: cors
               })

      assert service.cors == cors
    end

    test "creates service with access_control config" do
      project = project_fixture()

      ac = %{"allow" => "10.0.0.0/8", "deny" => "0.0.0.0/0", "mode" => "deny_first"}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "ACL Service",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 access_control: ac
               })

      assert service.access_control == ac
    end

    test "creates service with compression config" do
      project = project_fixture()

      comp = %{"algorithms" => "gzip, brotli", "min_size" => 1024}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Comp Service",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 compression: comp
               })

      assert service.compression == comp
    end

    test "creates service with path_rewrite config" do
      project = project_fixture()

      pr = %{"strip_prefix" => "/api/v1", "add_prefix" => "/v2"}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Rewrite Service",
                 route_path: "/api/v1/*",
                 upstream_url: "http://localhost:3000",
                 path_rewrite: pr
               })

      assert service.path_rewrite == pr
    end

    test "returns error for duplicate slug within project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_service(%{
          project_id: project.id,
          name: "My Service",
          route_path: "/api/*",
          upstream_url: "http://localhost:3000"
        })

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "My Service",
                 route_path: "/api/v2/*",
                 upstream_url: "http://localhost:3001"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Services.create_service(%{
                 project_id: p1.id,
                 name: "API",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000"
               })

      assert {:ok, _} =
               Services.create_service(%{
                 project_id: p2.id,
                 name: "API",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000"
               })
    end

    test "creates a static response service" do
      project = project_fixture()

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Health",
                 route_path: "/health",
                 respond_status: 200,
                 respond_body: "OK"
               })

      assert service.respond_status == 200
      assert service.respond_body == "OK"
      assert is_nil(service.upstream_url)
    end
  end

  describe "list_services/2" do
    test "returns services for a project ordered by position" do
      project = project_fixture()
      _s1 = service_fixture(%{project: project, name: "Second", position: 1})
      _s2 = service_fixture(%{project: project, name: "First", position: 0})

      services = Services.list_services(project.id)
      assert length(services) == 2
      assert hd(services).name == "First"
    end

    test "filters by enabled" do
      project = project_fixture()
      _s1 = service_fixture(%{project: project, name: "Enabled"})

      _s2 =
        service_fixture(%{project: project, name: "Disabled", enabled: false})

      enabled = Services.list_services(project.id, enabled: true)
      assert length(enabled) == 1
      assert hd(enabled).name == "Enabled"
    end

    test "does not include services from other projects" do
      project = project_fixture()
      other = project_fixture()
      _s1 = service_fixture(%{project: project})
      _s2 = service_fixture(%{project: other})

      services = Services.list_services(project.id)
      assert length(services) == 1
    end
  end

  describe "get_service/1" do
    test "returns service by id" do
      service = service_fixture()
      found = Services.get_service(service.id)
      assert found.id == service.id
    end

    test "returns nil for unknown id" do
      refute Services.get_service(Ecto.UUID.generate())
    end
  end

  describe "update_service/2" do
    test "updates a service" do
      service = service_fixture()

      assert {:ok, updated} =
               Services.update_service(service, %{name: "Updated", route_path: "/new/*"})

      assert updated.name == "Updated"
      assert updated.route_path == "/new/*"
    end

    test "validates on update" do
      service = service_fixture()

      assert {:error, changeset} =
               Services.update_service(service, %{route_path: "no-slash"})

      assert %{route_path: ["must start with /"]} = errors_on(changeset)
    end
  end

  describe "delete_service/1" do
    test "deletes a service" do
      service = service_fixture()
      assert {:ok, _} = Services.delete_service(service)
      refute Services.get_service(service.id)
    end
  end

  describe "reorder_services/2" do
    test "updates positions for services" do
      project = project_fixture()
      s1 = service_fixture(%{project: project, name: "A", position: 0})
      s2 = service_fixture(%{project: project, name: "B", position: 1})

      {:ok, :ok} = Services.reorder_services(project.id, [{s2.id, 0}, {s1.id, 1}])

      services = Services.list_services(project.id)
      assert hd(services).id == s2.id
    end
  end

  describe "service with security config" do
    test "creates service with security config" do
      project = project_fixture()

      security = %{
        "max_body_size" => 1_048_576,
        "block_sqli" => "true",
        "block_xss" => "true"
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Secure API",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 security: security
               })

      assert service.security == security
    end

    test "updates service security config" do
      service = service_fixture()

      security = %{"max_body_size" => 2_097_152, "allowed_content_types" => "application/json"}

      assert {:ok, updated} = Services.update_service(service, %{security: security})
      assert updated.security == security
    end
  end

  describe "service with transform configs" do
    test "creates service with request_transform" do
      project = project_fixture()

      rt = %{"add_headers" => "X-Custom: value", "remove_headers" => "X-Forwarded-For"}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Transform API",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 request_transform: rt
               })

      assert service.request_transform == rt
    end

    test "creates service with response_transform" do
      project = project_fixture()

      rt = %{"add_headers" => "X-Frame-Options: DENY", "remove_headers" => "Server"}

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Response Transform API",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 response_transform: rt
               })

      assert service.response_transform == rt
    end

    test "updates service transform configs" do
      service = service_fixture()

      req_t = %{"add_headers" => "X-Req: true"}
      res_t = %{"remove_headers" => "Server"}

      assert {:ok, updated} =
               Services.update_service(service, %{
                 request_transform: req_t,
                 response_transform: res_t
               })

      assert updated.request_transform == req_t
      assert updated.response_transform == res_t
    end
  end

  describe "service with auth_policy_id" do
    test "creates service bound to auth policy" do
      project = project_fixture()
      policy = auth_policy_fixture(%{project: project})

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Authed API",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 auth_policy_id: policy.id
               })

      assert service.auth_policy_id == policy.id
    end

    test "can update service auth_policy_id" do
      project = project_fixture()
      policy = auth_policy_fixture(%{project: project})
      service = service_fixture(%{project: project})

      assert {:ok, updated} =
               Services.update_service(service, %{auth_policy_id: policy.id})

      assert updated.auth_policy_id == policy.id
    end

    test "can clear auth_policy_id" do
      project = project_fixture()
      policy = auth_policy_fixture(%{project: project})

      {:ok, service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Authed",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          auth_policy_id: policy.id
        })

      assert {:ok, updated} = Services.update_service(service, %{auth_policy_id: nil})
      assert is_nil(updated.auth_policy_id)
    end
  end

  describe "service with traffic_split" do
    test "creates service with traffic_split config" do
      project = project_fixture()

      traffic_split = %{
        "splits" => [
          %{"upstream_group_id" => Ecto.UUID.generate(), "weight" => 80},
          %{"upstream_group_id" => Ecto.UUID.generate(), "weight" => 20}
        ],
        "match_rules" => [
          %{
            "type" => "header",
            "header" => "X-Version",
            "value" => "v2",
            "target_group_id" => Ecto.UUID.generate()
          }
        ]
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Split Service",
                 route_path: "/api/*",
                 upstream_url: "http://localhost:3000",
                 traffic_split: traffic_split
               })

      assert service.traffic_split == traffic_split
      assert length(service.traffic_split["splits"]) == 2
      assert length(service.traffic_split["match_rules"]) == 1
    end

    test "updates service traffic_split config" do
      service = service_fixture()

      traffic_split = %{
        "splits" => [
          %{"upstream_group_id" => Ecto.UUID.generate(), "weight" => 50},
          %{"upstream_group_id" => Ecto.UUID.generate(), "weight" => 50}
        ]
      }

      assert {:ok, updated} = Services.update_service(service, %{traffic_split: traffic_split})
      assert updated.traffic_split == traffic_split
    end

    test "clears traffic_split config" do
      project = project_fixture()

      {:ok, service} =
        Services.create_service(%{
          project_id: project.id,
          name: "Split",
          route_path: "/api/*",
          upstream_url: "http://api:8080",
          traffic_split: %{
            "splits" => [%{"upstream_group_id" => Ecto.UUID.generate(), "weight" => 100}]
          }
        })

      assert {:ok, updated} = Services.update_service(service, %{traffic_split: %{}})
      assert updated.traffic_split == %{}
    end
  end

  describe "inference service" do
    test "creates inference service with valid config" do
      project = project_fixture()

      inference = %{
        "provider" => "openai",
        "token_rate_limit" => %{"tokens_per_minute" => 100_000},
        "streaming" => %{"enabled" => true, "format" => "sse"}
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "LLM Gateway",
                 route_path: "/v1/*",
                 upstream_url: "http://inference:8080",
                 service_type: "inference",
                 inference: inference
               })

      assert service.service_type == "inference"
      assert service.inference["provider"] == "openai"
    end

    test "rejects inference service without provider" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad Inference",
                 route_path: "/v1/*",
                 upstream_url: "http://inference:8080",
                 service_type: "inference",
                 inference: %{"token_rate_limit" => %{"tokens_per_minute" => 1000}}
               })

      assert %{inference: [msg]} = errors_on(changeset)
      assert msg =~ "valid provider"
    end

    test "rejects inference service with empty inference config" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Empty Inference",
                 route_path: "/v1/*",
                 upstream_url: "http://inference:8080",
                 service_type: "inference",
                 inference: %{}
               })

      assert %{inference: [msg]} = errors_on(changeset)
      assert msg =~ "required when service_type is inference"
    end

    test "rejects non-empty inference config on standard service" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Standard With Inference",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 service_type: "standard",
                 inference: %{"provider" => "openai"}
               })

      assert %{inference: [msg]} = errors_on(changeset)
      assert msg =~ "must be empty"
    end

    test "filters services by service_type" do
      project = project_fixture()

      _standard = service_fixture(%{project: project, name: "Standard API"})

      {:ok, _inference} =
        Services.create_service(%{
          project_id: project.id,
          name: "LLM Service",
          route_path: "/v1/*",
          upstream_url: "http://inference:8080",
          service_type: "inference",
          inference: %{"provider" => "openai"}
        })

      inference_services = Services.list_services(project.id, service_type: "inference")
      assert length(inference_services) == 1
      assert hd(inference_services).name == "LLM Service"

      standard_services = Services.list_services(project.id, service_type: "standard")
      assert length(standard_services) == 1
      assert hd(standard_services).name == "Standard API"
    end
  end

  describe "grpc service" do
    test "creates grpc service with valid config" do
      project = project_fixture()

      grpc = %{
        "max_message_size" => 4_194_304,
        "reflection" => "true",
        "health_check_service" => "grpc.health.v1.Health"
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "gRPC Gateway",
                 route_path: "/grpc/*",
                 upstream_url: "http://grpc:9090",
                 service_type: "grpc",
                 grpc: grpc
               })

      assert service.service_type == "grpc"
      assert service.grpc == grpc
    end

    test "rejects grpc service with empty grpc config" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad gRPC",
                 route_path: "/grpc/*",
                 upstream_url: "http://grpc:9090",
                 service_type: "grpc",
                 grpc: %{}
               })

      assert %{grpc: [msg]} = errors_on(changeset)
      assert msg =~ "required when service_type is grpc"
    end

    test "rejects grpc config on standard service" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Standard With gRPC",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 service_type: "standard",
                 grpc: %{"reflection" => "true"}
               })

      assert %{grpc: [msg]} = errors_on(changeset)
      assert msg =~ "must be empty"
    end
  end

  describe "websocket service" do
    test "creates websocket service with valid config" do
      project = project_fixture()

      websocket = %{
        "ping_interval" => 30,
        "max_message_size" => 65_536,
        "max_connections" => 10_000
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "WS Gateway",
                 route_path: "/ws/*",
                 upstream_url: "http://ws:8080",
                 service_type: "websocket",
                 websocket: websocket
               })

      assert service.service_type == "websocket"
      assert service.websocket == websocket
    end

    test "rejects websocket service with empty websocket config" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad WS",
                 route_path: "/ws/*",
                 upstream_url: "http://ws:8080",
                 service_type: "websocket",
                 websocket: %{}
               })

      assert %{websocket: [msg]} = errors_on(changeset)
      assert msg =~ "required when service_type is websocket"
    end

    test "rejects websocket config on standard service" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Standard With WS",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 service_type: "standard",
                 websocket: %{"ping_interval" => 30}
               })

      assert %{websocket: [msg]} = errors_on(changeset)
      assert msg =~ "must be empty"
    end
  end

  describe "graphql service" do
    test "creates graphql service with valid config" do
      project = project_fixture()

      graphql = %{
        "max_depth" => 10,
        "max_complexity" => 1000,
        "introspection" => "true"
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "GraphQL Gateway",
                 route_path: "/graphql",
                 upstream_url: "http://graphql:4000",
                 service_type: "graphql",
                 graphql: graphql
               })

      assert service.service_type == "graphql"
      assert service.graphql == graphql
    end

    test "rejects graphql service with empty graphql config" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad GraphQL",
                 route_path: "/graphql",
                 upstream_url: "http://graphql:4000",
                 service_type: "graphql",
                 graphql: %{}
               })

      assert %{graphql: [msg]} = errors_on(changeset)
      assert msg =~ "required when service_type is graphql"
    end

    test "rejects graphql config on standard service" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Standard With GraphQL",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 service_type: "standard",
                 graphql: %{"max_depth" => 10}
               })

      assert %{graphql: [msg]} = errors_on(changeset)
      assert msg =~ "must be empty"
    end
  end

  describe "streaming service" do
    test "creates streaming service with valid config" do
      project = project_fixture()

      streaming = %{
        "format" => "sse",
        "keepalive_interval" => 15,
        "max_connection_duration" => 3600,
        "buffer_size" => 1024
      }

      assert {:ok, %Service{} = service} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "SSE Service",
                 route_path: "/events/*",
                 upstream_url: "http://streaming:8080",
                 service_type: "streaming",
                 streaming: streaming
               })

      assert service.service_type == "streaming"
      assert service.streaming == streaming
    end

    test "rejects streaming service with empty streaming config" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Bad Streaming",
                 route_path: "/events/*",
                 upstream_url: "http://streaming:8080",
                 service_type: "streaming",
                 streaming: %{}
               })

      assert %{streaming: [msg]} = errors_on(changeset)
      assert msg =~ "required when service_type is streaming"
    end

    test "rejects streaming config on standard service" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_service(%{
                 project_id: project.id,
                 name: "Standard With Streaming",
                 route_path: "/api/*",
                 upstream_url: "http://api:8080",
                 service_type: "standard",
                 streaming: %{"format" => "sse"}
               })

      assert %{streaming: [msg]} = errors_on(changeset)
      assert msg =~ "must be empty"
    end
  end

  describe "upstream group with circuit_breaker" do
    test "creates upstream group with circuit_breaker config" do
      project = project_fixture()

      cb = %{
        "failure_threshold" => 5,
        "success_threshold" => 3,
        "timeout" => 30,
        "half_open_max_requests" => 1
      }

      assert {:ok, group} =
               Services.create_upstream_group(%{
                 project_id: project.id,
                 name: "CB Group",
                 circuit_breaker: cb
               })

      assert group.circuit_breaker == cb
    end

    test "updates upstream group circuit_breaker config" do
      project = project_fixture()

      {:ok, group} =
        Services.create_upstream_group(%{
          project_id: project.id,
          name: "CB Group"
        })

      cb = %{"failure_threshold" => 10, "timeout" => 60}

      assert {:ok, updated} = Services.update_upstream_group(group, %{circuit_breaker: cb})
      assert updated.circuit_breaker == cb
    end
  end

  describe "get_or_create_project_config/1" do
    test "creates config if not exists" do
      project = project_fixture()
      assert {:ok, %ProjectConfig{} = config} = Services.get_or_create_project_config(project.id)
      assert config.log_level == "info"
      assert config.metrics_port == 9090
    end

    test "returns existing config" do
      project = project_fixture()
      {:ok, config1} = Services.get_or_create_project_config(project.id)
      {:ok, config2} = Services.get_or_create_project_config(project.id)
      assert config1.id == config2.id
    end
  end

  describe "update_project_config/2" do
    test "updates config" do
      project = project_fixture()
      {:ok, config} = Services.get_or_create_project_config(project.id)

      assert {:ok, updated} =
               Services.update_project_config(config, %{
                 log_level: "debug",
                 metrics_port: 9191
               })

      assert updated.log_level == "debug"
      assert updated.metrics_port == 9191
    end

    test "validates log level" do
      project = project_fixture()
      {:ok, config} = Services.get_or_create_project_config(project.id)

      assert {:error, changeset} =
               Services.update_project_config(config, %{log_level: "invalid"})

      assert %{log_level: ["is invalid"]} = errors_on(changeset)
    end

    test "validates metrics port range" do
      project = project_fixture()
      {:ok, config} = Services.get_or_create_project_config(project.id)

      assert {:error, changeset} =
               Services.update_project_config(config, %{metrics_port: 0})

      assert errors_on(changeset)[:metrics_port]
    end
  end
end
