defmodule SentinelCp.Services.BuiltInTemplates do
  @moduledoc """
  Seeds built-in service templates.

  These templates provide best-practice defaults for common service patterns.
  They are created lazily on first access and are shared across all projects.
  """

  alias SentinelCp.Repo
  alias SentinelCp.Services.ServiceTemplate

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
