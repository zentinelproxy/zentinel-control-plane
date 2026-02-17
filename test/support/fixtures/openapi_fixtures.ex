defmodule ZentinelCp.OpenApiFixtures do
  @moduledoc """
  Fixtures for OpenAPI spec testing.
  """

  alias ZentinelCp.Services

  def petstore_spec_json do
    Jason.encode!(petstore_spec_map())
  end

  def petstore_spec_yaml do
    """
    openapi: "3.0.3"
    info:
      title: Petstore
      version: "1.0.0"
    servers:
      - url: https://api.petstore.io/v1
    paths:
      /pets:
        get:
          operationId: listPets
          summary: List all pets
          security:
            - bearerAuth: []
        post:
          operationId: createPet
          summary: Create a pet
      /pets/{petId}:
        get:
          operationId: showPetById
          summary: Info for a specific pet
    components:
      securitySchemes:
        bearerAuth:
          type: http
          scheme: bearer
          bearerFormat: JWT
        apiKeyAuth:
          type: apiKey
          name: X-API-Key
          in: header
    """
  end

  def petstore_spec_map do
    %{
      "openapi" => "3.0.3",
      "info" => %{
        "title" => "Petstore",
        "version" => "1.0.0"
      },
      "servers" => [
        %{"url" => "https://api.petstore.io/v1"}
      ],
      "paths" => %{
        "/pets" => %{
          "get" => %{
            "operationId" => "listPets",
            "summary" => "List all pets",
            "security" => [%{"bearerAuth" => []}]
          },
          "post" => %{
            "operationId" => "createPet",
            "summary" => "Create a pet"
          }
        },
        "/pets/{petId}" => %{
          "get" => %{
            "operationId" => "showPetById",
            "summary" => "Info for a specific pet"
          }
        }
      },
      "components" => %{
        "securitySchemes" => %{
          "bearerAuth" => %{
            "type" => "http",
            "scheme" => "bearer",
            "bearerFormat" => "JWT"
          },
          "apiKeyAuth" => %{
            "type" => "apiKey",
            "name" => "X-API-Key",
            "in" => "header"
          }
        }
      }
    }
  end

  def minimal_spec_map do
    %{
      "openapi" => "3.1.0",
      "info" => %{"title" => "Minimal", "version" => "0.1.0"},
      "paths" => %{
        "/health" => %{
          "get" => %{"summary" => "Health check"}
        }
      }
    }
  end

  def swagger2_spec_map do
    %{
      "swagger" => "2.0",
      "info" => %{"title" => "Old API", "version" => "1.0.0"},
      "paths" => %{}
    }
  end

  def spec_with_auth_types do
    %{
      "openapi" => "3.0.0",
      "info" => %{"title" => "Auth Test", "version" => "1.0.0"},
      "paths" => %{
        "/secure" => %{
          "get" => %{"summary" => "Secure endpoint"}
        }
      },
      "security" => [%{"oauth2Auth" => ["read"]}],
      "components" => %{
        "securitySchemes" => %{
          "basicAuth" => %{
            "type" => "http",
            "scheme" => "basic"
          },
          "oauth2Auth" => %{
            "type" => "oauth2",
            "flows" => %{
              "authorizationCode" => %{
                "authorizationUrl" => "https://auth.example.com/authorize",
                "tokenUrl" => "https://auth.example.com/token",
                "scopes" => %{"read" => "Read access"}
              }
            }
          },
          "oidcAuth" => %{
            "type" => "openIdConnect",
            "openIdConnectUrl" => "https://auth.example.com/.well-known/openid-configuration"
          },
          "mtlsAuth" => %{
            "type" => "mutualTLS"
          }
        }
      }
    }
  end

  def openapi_spec_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()
    spec_data = attrs[:spec_data] || petstore_spec_map()
    content = Jason.encode!(spec_data)

    {:ok, spec} =
      Services.create_openapi_spec(%{
        name: attrs[:name] || "petstore-#{System.unique_integer([:positive])}",
        file_name: attrs[:file_name] || "petstore.json",
        openapi_version: attrs[:openapi_version] || "3.0.3",
        spec_version: attrs[:spec_version] || "1.0.0",
        spec_data: spec_data,
        checksum:
          attrs[:checksum] || :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        paths_count: attrs[:paths_count] || map_size(spec_data["paths"] || %{}),
        project_id: project.id
      })

    spec
  end
end
