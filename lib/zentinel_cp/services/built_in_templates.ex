defmodule ZentinelCp.Services.BuiltInTemplates do
  @moduledoc """
  Seeds built-in service templates.

  These templates provide best-practice defaults for common service patterns.
  They are created lazily on first access and are shared across all projects.
  """

  alias ZentinelCp.Repo
  alias ZentinelCp.Services.ServiceTemplate

  import Ecto.Query

  @templates [
    %{
      name: "REST API",
      category: "api",
      description: "Standard REST API service with CORS and rate limiting.",
      template_data: %{
        "upstream_url" => "http://api-backend:8080",
        "route_path" => "/api/*",
        "cors" => %{
          "allowed_origins" => "*",
          "allowed_methods" => "GET,POST,PUT,DELETE",
          "allowed_headers" => "Content-Type,Authorization",
          "max_age" => 86400
        },
        "rate_limit" => %{"requests" => 100, "window" => "60s", "by" => "client_ip"}
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "Web Application",
      category: "web",
      description: "Web application with compression, caching, and security headers.",
      template_data: %{
        "upstream_url" => "http://web-app:3000",
        "route_path" => "/*",
        "compression" => %{"algorithms" => "gzip,brotli"},
        "cache" => %{"ttl" => 3600},
        "response_transform" => %{
          "add_headers" => "X-Frame-Options: DENY\nX-Content-Type-Options: nosniff"
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "WebSocket Service",
      category: "websocket",
      description: "WebSocket service with extended timeout and no rate limiting.",
      template_data: %{
        "upstream_url" => "http://ws-backend:8080",
        "route_path" => "/ws/*",
        "timeout_seconds" => 300,
        "headers" => %{"Upgrade" => "websocket", "Connection" => "Upgrade"}
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "Static Files",
      category: "static",
      description: "Static file serving with aggressive caching and compression.",
      template_data: %{
        "upstream_url" => "http://cdn:80",
        "route_path" => "/static/*",
        "cache" => %{"ttl" => 86400},
        "compression" => %{"algorithms" => "gzip,brotli,zstd"},
        "response_transform" => %{
          "add_headers" => "X-Content-Type-Options: nosniff"
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "Auth-Protected API",
      category: "auth",
      description: "API with CORS, rate limiting, and WAF security rules.",
      template_data: %{
        "upstream_url" => "http://api-backend:8080",
        "route_path" => "/api/*",
        "cors" => %{
          "allowed_origins" => "*",
          "allowed_methods" => "GET,POST,PUT,DELETE"
        },
        "rate_limit" => %{"requests" => 60, "window" => "60s", "by" => "client_ip"},
        "security" => %{"block_sqli" => "true", "block_xss" => "true"}
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "Health Endpoint",
      category: "utility",
      description: "Simple health check endpoint returning 200 OK.",
      template_data: %{
        "route_path" => "/health",
        "respond_status" => 200,
        "respond_body" => "OK"
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "LLM Inference Gateway",
      category: "inference",
      description: "AI inference gateway with token rate limiting, cost tracking, and streaming.",
      template_data: %{
        "upstream_url" => "http://inference-backend:8080",
        "route_path" => "/v1/*",
        "service_type" => "inference",
        "timeout_seconds" => 300,
        "inference" => %{
          "provider" => "openai",
          "token_rate_limit" => %{"tokens_per_minute" => 100_000, "burst_allowance" => 1.5},
          "token_budget" => %{
            "period" => "monthly",
            "limit" => 10_000_000,
            "alert_threshold" => 0.8,
            "enforcement" => "block"
          },
          "cost_attribution" => %{
            "currency" => "USD",
            "models" => [
              %{"pattern" => "*", "input_cost_per_1k" => 0.01, "output_cost_per_1k" => 0.03}
            ]
          },
          "streaming" => %{"enabled" => true, "format" => "sse"}
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "gRPC Gateway",
      category: "grpc",
      description: "gRPC gateway with reflection and health checking.",
      template_data: %{
        "upstream_url" => "http://grpc-backend:9090",
        "route_path" => "/grpc/*",
        "service_type" => "grpc",
        "grpc" => %{
          "max_message_size" => 4_194_304,
          "reflection" => "true",
          "health_check_service" => "grpc.health.v1.Health"
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "WebSocket Gateway",
      category: "websocket",
      description: "WebSocket gateway with connection management and ping/pong.",
      template_data: %{
        "upstream_url" => "http://ws-backend:8080",
        "route_path" => "/ws/*",
        "service_type" => "websocket",
        "timeout_seconds" => 300,
        "websocket" => %{
          "ping_interval" => 30,
          "max_message_size" => 65_536,
          "max_connections" => 10_000
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "GraphQL Gateway",
      category: "graphql",
      description:
        "GraphQL gateway with depth limiting, complexity analysis, and introspection control.",
      template_data: %{
        "upstream_url" => "http://graphql-backend:4000",
        "route_path" => "/graphql",
        "service_type" => "graphql",
        "graphql" => %{
          "max_depth" => 10,
          "max_complexity" => 1000,
          "introspection" => "true",
          "persisted_queries" => "false"
        }
      },
      is_builtin: true,
      version: 1
    },
    %{
      name: "SSE Streaming Service",
      category: "streaming",
      description: "Server-Sent Events streaming service with keepalive and buffering.",
      template_data: %{
        "upstream_url" => "http://streaming-backend:8080",
        "route_path" => "/events/*",
        "service_type" => "streaming",
        "timeout_seconds" => 600,
        "streaming" => %{
          "format" => "sse",
          "keepalive_interval" => 15,
          "max_connection_duration" => 3600,
          "buffer_size" => 1024
        }
      },
      is_builtin: true,
      version: 1
    }
  ]

  @doc """
  Ensures built-in templates exist in the database.
  Uses upsert semantics — inserts only if the slug doesn't exist.
  """
  def ensure_built_ins! do
    existing_slugs =
      from(t in ServiceTemplate, where: t.is_builtin == true, select: t.slug)
      |> Repo.all()
      |> MapSet.new()

    Enum.each(@templates, fn template ->
      slug =
        template.name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.replace(~r/^-+|-+$/, "")
        |> String.slice(0, 50)

      unless MapSet.member?(existing_slugs, slug) do
        %ServiceTemplate{}
        |> ServiceTemplate.create_changeset(template)
        |> Repo.insert!()
      end
    end)

    :ok
  end
end
