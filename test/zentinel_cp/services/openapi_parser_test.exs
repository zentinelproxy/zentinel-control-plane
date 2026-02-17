defmodule ZentinelCp.Services.OpenApiParserTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Services.OpenApiParser
  alias ZentinelCp.OpenApiFixtures

  describe "decode_spec_file/2" do
    test "decodes JSON file by extension" do
      json = OpenApiFixtures.petstore_spec_json()
      assert {:ok, map} = OpenApiParser.decode_spec_file(json, "petstore.json")
      assert map["openapi"] == "3.0.3"
    end

    test "decodes YAML file by .yaml extension" do
      yaml = OpenApiFixtures.petstore_spec_yaml()
      assert {:ok, map} = OpenApiParser.decode_spec_file(yaml, "petstore.yaml")
      assert map["openapi"] == "3.0.3"
    end

    test "decodes YAML file by .yml extension" do
      yaml = OpenApiFixtures.petstore_spec_yaml()
      assert {:ok, map} = OpenApiParser.decode_spec_file(yaml, "spec.yml")
      assert map["openapi"] == "3.0.3"
    end

    test "auto-detects JSON for unknown extension" do
      json = OpenApiFixtures.petstore_spec_json()
      assert {:ok, map} = OpenApiParser.decode_spec_file(json, "spec.txt")
      assert map["openapi"] == "3.0.3"
    end

    test "auto-detects YAML for unknown extension" do
      yaml = OpenApiFixtures.petstore_spec_yaml()
      assert {:ok, _map} = OpenApiParser.decode_spec_file(yaml, "spec.txt")
    end

    test "returns error for invalid JSON" do
      assert {:error, msg} = OpenApiParser.decode_spec_file("{bad", "spec.json")
      assert msg =~ "Invalid JSON"
    end

    test "returns error for invalid YAML" do
      assert {:error, msg} = OpenApiParser.decode_spec_file(":\n  :\n  invalid: [", "spec.yaml")
      assert msg =~ "Invalid YAML"
    end
  end

  describe "parse/1" do
    test "parses valid OpenAPI 3.0.x spec" do
      raw = OpenApiFixtures.petstore_spec_map()
      assert {:ok, parsed} = OpenApiParser.parse(raw)
      assert parsed.openapi_version == "3.0.3"
      assert parsed.info["title"] == "Petstore"
      assert map_size(parsed.paths) == 2
      assert map_size(parsed.security_schemes) == 2
    end

    test "parses valid OpenAPI 3.1.x spec" do
      raw = OpenApiFixtures.minimal_spec_map()
      assert {:ok, parsed} = OpenApiParser.parse(raw)
      assert parsed.openapi_version == "3.1.0"
    end

    test "rejects Swagger 2.x with helpful message" do
      raw = OpenApiFixtures.swagger2_spec_map()
      assert {:error, msg} = OpenApiParser.parse(raw)
      assert msg =~ "Swagger 2.x is not supported"
    end

    test "rejects spec without openapi field" do
      assert {:error, msg} = OpenApiParser.parse(%{"info" => %{}})
      assert msg =~ "missing 'openapi' version field"
    end

    test "rejects unsupported version" do
      raw = %{"openapi" => "2.0.0", "paths" => %{}}
      assert {:error, msg} = OpenApiParser.parse(raw)
      assert msg =~ "Unsupported OpenAPI version"
    end

    test "handles spec without servers or components" do
      raw = OpenApiFixtures.minimal_spec_map()
      assert {:ok, parsed} = OpenApiParser.parse(raw)
      assert parsed.servers == []
      assert parsed.security_schemes == %{}
      assert parsed.global_security == []
    end
  end

  describe "extract_services/2" do
    test "extracts one service per path" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      assert length(services) == 2
    end

    test "converts path parameters to wildcards" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      pet_by_id = Enum.find(services, &(&1.openapi_path == "/pets/{petId}"))
      assert pet_by_id.route_path == "/v1/pets/*"
    end

    test "prepends base path from server URL" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      pets = Enum.find(services, &(&1.openapi_path == "/pets"))
      assert pets.route_path == "/v1/pets"
    end

    test "uses operationId as service name when available" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      pets = Enum.find(services, &(&1.openapi_path == "/pets"))
      assert pets.name == "listPets"
    end

    test "falls back to humanized path when no operationId" do
      spec = %{
        "openapi" => "3.0.0",
        "info" => %{"title" => "Test", "version" => "1.0.0"},
        "paths" => %{
          "/users/profile" => %{
            "get" => %{"summary" => "Get profile"}
          }
        }
      }

      {:ok, parsed} = OpenApiParser.parse(spec)
      services = OpenApiParser.extract_services(parsed)

      assert hd(services).name == "users profile"
    end

    test "extracts methods per path" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      pets = Enum.find(services, &(&1.openapi_path == "/pets"))
      assert "GET" in pets.methods
      assert "POST" in pets.methods
    end

    test "uses upstream_url override" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed, upstream_url: "http://custom:9090")

      assert Enum.all?(services, &(&1.upstream_url == "http://custom:9090"))
    end

    test "extracts upstream from server URL" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      assert hd(services).upstream_url == "https://api.petstore.io"
    end

    test "defaults upstream for specs without servers" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.minimal_spec_map())
      services = OpenApiParser.extract_services(parsed)

      assert hd(services).upstream_url == "http://localhost:8080"
    end

    test "collects security refs per path" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      pets = Enum.find(services, &(&1.openapi_path == "/pets"))
      assert "bearerAuth" in pets.security_refs
    end

    test "sets openapi_path on each service" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      services = OpenApiParser.extract_services(parsed)

      assert Enum.all?(services, &is_binary(&1.openapi_path))
    end
  end

  describe "extract_auth_policies/1" do
    test "maps http/bearer to jwt" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      policies = OpenApiParser.extract_auth_policies(parsed)

      bearer = Enum.find(policies, &(&1.name == "bearerAuth"))
      assert bearer.auth_type == "jwt"
      assert bearer.config["bearerFormat"] == "JWT"
    end

    test "maps apiKey to api_key" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      policies = OpenApiParser.extract_auth_policies(parsed)

      api_key = Enum.find(policies, &(&1.name == "apiKeyAuth"))
      assert api_key.auth_type == "api_key"
      assert api_key.config["header_name"] == "X-API-Key"
      assert api_key.config["location"] == "header"
    end

    test "maps http/basic to basic" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.spec_with_auth_types())
      policies = OpenApiParser.extract_auth_policies(parsed)

      basic = Enum.find(policies, &(&1.name == "basicAuth"))
      assert basic.auth_type == "basic"
    end

    test "maps oauth2 to jwt with flows" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.spec_with_auth_types())
      policies = OpenApiParser.extract_auth_policies(parsed)

      oauth = Enum.find(policies, &(&1.name == "oauth2Auth"))
      assert oauth.auth_type == "jwt"
      assert is_map(oauth.config["flows"])
    end

    test "maps openIdConnect to jwt" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.spec_with_auth_types())
      policies = OpenApiParser.extract_auth_policies(parsed)

      oidc = Enum.find(policies, &(&1.name == "oidcAuth"))
      assert oidc.auth_type == "jwt"
      assert oidc.config["openid_connect_url"] =~ "well-known"
    end

    test "maps mutualTLS to mtls" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.spec_with_auth_types())
      policies = OpenApiParser.extract_auth_policies(parsed)

      mtls = Enum.find(policies, &(&1.name == "mtlsAuth"))
      assert mtls.auth_type == "mtls"
    end

    test "returns empty list for spec without security schemes" do
      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.minimal_spec_map())
      assert OpenApiParser.extract_auth_policies(parsed) == []
    end
  end

  describe "diff_specs/2" do
    test "detects added paths" do
      {:ok, old} = OpenApiParser.parse(OpenApiFixtures.minimal_spec_map())
      {:ok, new} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())

      diff = OpenApiParser.diff_specs(old, new)
      assert "/pets" in diff.added
      assert "/pets/{petId}" in diff.added
    end

    test "detects removed paths" do
      {:ok, old} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      {:ok, new} = OpenApiParser.parse(OpenApiFixtures.minimal_spec_map())

      diff = OpenApiParser.diff_specs(old, new)
      assert "/pets" in diff.removed
      assert "/pets/{petId}" in diff.removed
    end

    test "detects unchanged paths" do
      {:ok, spec} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())

      diff = OpenApiParser.diff_specs(spec, spec)
      assert diff.added == []
      assert diff.removed == []
      assert length(diff.unchanged) == 2
    end

    test "handles empty specs" do
      empty = %{paths: %{}}
      {:ok, spec} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())

      diff = OpenApiParser.diff_specs(empty, spec)
      assert length(diff.added) == 2
      assert diff.removed == []
      assert diff.unchanged == []
    end
  end
end
