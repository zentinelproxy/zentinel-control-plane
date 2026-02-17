defmodule ZentinelCp.Services.MiddlewareTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services
  alias ZentinelCp.Services.{Middleware, ServiceMiddleware, KdlGenerator, ProjectConfig}

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.MiddlewareFixtures

  ## Middleware CRUD

  describe "create_middleware/1" do
    test "creates middleware with valid attributes" do
      project = project_fixture()

      assert {:ok, %Middleware{} = mw} =
               Services.create_middleware(%{
                 project_id: project.id,
                 name: "Standard CORS",
                 middleware_type: "cors",
                 config: %{"allow_origins" => "*"}
               })

      assert mw.name == "Standard CORS"
      assert mw.slug == "standard-cors"
      assert mw.middleware_type == "cors"
      assert mw.config["allow_origins"] == "*"
      assert mw.enabled == true
    end

    test "auto-generates slug from name" do
      project = project_fixture()

      {:ok, mw} =
        Services.create_middleware(%{
          project_id: project.id,
          name: "My Rate Limiter!",
          middleware_type: "rate_limit"
        })

      assert mw.slug == "my-rate-limiter"
    end

    test "validates middleware_type inclusion" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_middleware(%{
                 project_id: project.id,
                 name: "Bad Type",
                 middleware_type: "invalid"
               })

      assert %{middleware_type: ["is invalid"]} = errors_on(changeset)
    end

    test "validates required fields" do
      assert {:error, changeset} = Services.create_middleware(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:middleware_type]
      assert errors[:project_id]
    end

    test "enforces unique slug within project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_middleware(%{
          project_id: project.id,
          name: "CORS Policy",
          middleware_type: "cors"
        })

      assert {:error, changeset} =
               Services.create_middleware(%{
                 project_id: project.id,
                 name: "CORS Policy",
                 middleware_type: "cors"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Services.create_middleware(%{
                 project_id: p1.id,
                 name: "CORS",
                 middleware_type: "cors"
               })

      assert {:ok, _} =
               Services.create_middleware(%{
                 project_id: p2.id,
                 name: "CORS",
                 middleware_type: "cors"
               })
    end

    test "creates each middleware type" do
      project = project_fixture()

      for type <- Middleware.middleware_types() do
        assert {:ok, mw} =
                 Services.create_middleware(%{
                   project_id: project.id,
                   name: "#{type} middleware",
                   middleware_type: type
                 })

        assert mw.middleware_type == type
      end
    end
  end

  describe "list_middlewares/1" do
    test "returns middlewares for a project ordered by name" do
      project = project_fixture()
      _m1 = middleware_fixture(%{project: project, name: "Zeta"})
      _m2 = middleware_fixture(%{project: project, name: "Alpha"})

      middlewares = Services.list_middlewares(project.id)
      assert length(middlewares) == 2
      assert hd(middlewares).name == "Alpha"
    end

    test "does not include middlewares from other projects" do
      project = project_fixture()
      other = project_fixture()
      _m1 = middleware_fixture(%{project: project})
      _m2 = middleware_fixture(%{project: other})

      assert length(Services.list_middlewares(project.id)) == 1
    end
  end

  describe "list_middlewares_by_type/2" do
    test "filters by type" do
      project = project_fixture()
      _cors = middleware_fixture(%{project: project, middleware_type: "cors", name: "CORS"})
      _cache = middleware_fixture(%{project: project, middleware_type: "cache", name: "Cache"})

      cors_list = Services.list_middlewares_by_type(project.id, "cors")
      assert length(cors_list) == 1
      assert hd(cors_list).middleware_type == "cors"
    end
  end

  describe "get_middleware/1" do
    test "returns middleware by id" do
      mw = middleware_fixture()
      found = Services.get_middleware(mw.id)
      assert found.id == mw.id
    end

    test "returns nil for unknown id" do
      refute Services.get_middleware(Ecto.UUID.generate())
    end
  end

  describe "update_middleware/2" do
    test "updates a middleware" do
      mw = middleware_fixture()

      assert {:ok, updated} =
               Services.update_middleware(mw, %{
                 name: "Updated Middleware",
                 config: %{"allow_origins" => "https://example.com"}
               })

      assert updated.name == "Updated Middleware"
      assert updated.config["allow_origins"] == "https://example.com"
    end

    test "does not allow changing middleware_type" do
      mw = middleware_fixture(%{middleware_type: "cors"})

      {:ok, updated} = Services.update_middleware(mw, %{middleware_type: "cache"})
      # middleware_type is not in update_changeset cast fields
      assert updated.middleware_type == "cors"
    end
  end

  describe "delete_middleware/1" do
    test "deletes a middleware" do
      mw = middleware_fixture()
      assert {:ok, _} = Services.delete_middleware(mw)
      refute Services.get_middleware(mw.id)
    end

    test "cascades to service_middlewares" do
      project = project_fixture()
      mw = middleware_fixture(%{project: project})
      service = service_fixture(%{project: project})

      {:ok, sm} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      {:ok, _} = Services.delete_middleware(mw)
      refute Services.get_service_middleware(sm.id)
    end
  end

  ## Service Middleware Chain

  describe "attach_middleware/1" do
    test "attaches middleware to service" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project})

      assert {:ok, %ServiceMiddleware{} = sm} =
               Services.attach_middleware(%{
                 service_id: service.id,
                 middleware_id: mw.id,
                 position: 1
               })

      assert sm.service_id == service.id
      assert sm.middleware_id == mw.id
      assert sm.position == 1
      assert sm.enabled == true
    end

    test "prevents duplicate attachment" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project})

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      assert {:error, changeset} =
               Services.attach_middleware(%{
                 service_id: service.id,
                 middleware_id: mw.id,
                 position: 1
               })

      assert %{service_id: _} = errors_on(changeset)
    end

    test "allows config_override" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project, config: %{"ttl" => 60}})

      {:ok, sm} =
        Services.attach_middleware(%{
          service_id: service.id,
          middleware_id: mw.id,
          position: 0,
          config_override: %{"ttl" => 120}
        })

      assert sm.config_override["ttl"] == 120
    end
  end

  describe "list_service_middlewares/1" do
    test "returns middlewares ordered by position" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw1 = middleware_fixture(%{project: project, name: "B Second"})
      mw2 = middleware_fixture(%{project: project, name: "A First"})

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw1.id, position: 2})

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw2.id, position: 1})

      chain = Services.list_service_middlewares(service.id)
      assert length(chain) == 2
      assert hd(chain).position == 1
      assert hd(chain).middleware.name == "A First"
    end

    test "preloads middleware" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project})

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      [sm] = Services.list_service_middlewares(service.id)
      assert %Middleware{} = sm.middleware
      assert sm.middleware.id == mw.id
    end
  end

  describe "detach_middleware/1" do
    test "removes middleware from service" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project})

      {:ok, sm} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      assert {:ok, _} = Services.detach_middleware(sm)
      assert Services.list_service_middlewares(service.id) == []
    end
  end

  describe "update_service_middleware/2" do
    test "updates position and enabled" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw = middleware_fixture(%{project: project})

      {:ok, sm} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      {:ok, updated} = Services.update_service_middleware(sm, %{position: 5, enabled: false})
      assert updated.position == 5
      assert updated.enabled == false
    end
  end

  describe "reorder_service_middlewares/2" do
    test "batch updates positions" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      mw1 = middleware_fixture(%{project: project, name: "First"})
      mw2 = middleware_fixture(%{project: project, name: "Second"})

      {:ok, sm1} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw1.id, position: 0})

      {:ok, sm2} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw2.id, position: 1})

      assert {:ok, :ok} =
               Services.reorder_service_middlewares(service.id, [
                 {sm1.id, 2},
                 {sm2.id, 1}
               ])

      chain = Services.list_service_middlewares(service.id)
      assert hd(chain).middleware.name == "Second"
      assert List.last(chain).middleware.name == "First"
    end
  end

  ## KDL Generation with Middleware

  describe "KDL middleware chain generation" do
    test "generates KDL with middleware blocks after inline fields" do
      project = project_fixture()
      service = service_fixture(%{project: project, cors: %{"allow_origins" => "*"}})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      # Create middleware and attach
      mw =
        middleware_fixture(%{
          project: project,
          name: "Global Compression",
          middleware_type: "compression",
          config: %{"algorithm" => "gzip", "level" => 6}
        })

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)

      # Should contain inline cors block
      assert kdl =~ "cors {"
      assert kdl =~ "allow_origins"
      # Should also contain middleware compression block
      assert kdl =~ "compression {"
      assert kdl =~ "algorithm \"gzip\""
      assert kdl =~ "level 6"
    end

    test "respects middleware position order" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw1 =
        middleware_fixture(%{
          project: project,
          name: "CORS MW",
          middleware_type: "cors",
          config: %{"allow_origins" => "*"}
        })

      mw2 =
        middleware_fixture(%{
          project: project,
          name: "Cache MW",
          middleware_type: "cache",
          config: %{"ttl" => 300}
        })

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw1.id, position: 1})

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw2.id, position: 0})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)

      # cache (position 0) should appear before cors (position 1)
      cache_pos = :binary.match(kdl, "cache {") |> elem(0)
      cors_pos = :binary.match(kdl, "cors {") |> elem(0)
      assert cache_pos < cors_pos
    end

    test "skips disabled service middlewares" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw =
        middleware_fixture(%{
          project: project,
          name: "Disabled CORS",
          middleware_type: "cors",
          config: %{"allow_origins" => "*"}
        })

      {:ok, sm} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      {:ok, _} = Services.update_service_middleware(sm, %{enabled: false})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)
      refute kdl =~ "cors {"
    end

    test "skips disabled middleware definitions" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw =
        middleware_fixture(%{
          project: project,
          name: "Disabled MW",
          middleware_type: "cors",
          config: %{"allow_origins" => "*"},
          enabled: false
        })

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)
      refute kdl =~ "cors {"
    end

    test "config_override merges over base config" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw =
        middleware_fixture(%{
          project: project,
          name: "Cache",
          middleware_type: "cache",
          config: %{"ttl" => 60, "max_size" => 1000}
        })

      {:ok, _} =
        Services.attach_middleware(%{
          service_id: service.id,
          middleware_id: mw.id,
          position: 0,
          config_override: %{"ttl" => 300}
        })

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)

      # Should use overridden ttl
      assert kdl =~ "ttl 300"
      refute kdl =~ "ttl 60"
      # Should keep base max_size
      assert kdl =~ "max_size 1000"
    end

    test "auth type middleware generates auth block" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw =
        middleware_fixture(%{
          project: project,
          name: "JWT Auth",
          middleware_type: "auth",
          config: %{"type" => "jwt", "issuer" => "https://auth.example.com"}
        })

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)

      assert kdl =~ "auth {"
      assert kdl =~ "type \"jwt\""
      assert kdl =~ "issuer \"https://auth.example.com\""
    end

    test "custom type uses kdl_block_name" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      mw =
        middleware_fixture(%{
          project: project,
          name: "Custom Plugin",
          middleware_type: "custom",
          config: %{"kdl_block_name" => "my_plugin", "timeout" => 30, "retries" => 3}
        })

      {:ok, _} =
        Services.attach_middleware(%{service_id: service.id, middleware_id: mw.id, position: 0})

      chain = Services.list_service_middlewares(service.id)
      middleware_chains = %{service.id => chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], middleware_chains)

      assert kdl =~ "my_plugin {"
      assert kdl =~ "retries 3"
      assert kdl =~ "timeout 30"
      # kdl_block_name should not appear as a config key
      refute kdl =~ "kdl_block_name"
    end

    test "no middleware chain produces same output as before" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      kdl_without = KdlGenerator.build_kdl([service], config)
      kdl_with = KdlGenerator.build_kdl([service], config, [], [], [], %{})

      assert kdl_without == kdl_with
    end
  end
end
