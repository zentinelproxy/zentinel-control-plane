defmodule ZentinelCp.Services.OpenApiParser do
  @moduledoc """
  Pure-function module for parsing OpenAPI 3.x specifications.

  No database access — all functions operate on in-memory data structures.
  """

  @supported_versions ["3.0", "3.1"]

  @doc """
  Decodes a spec file from raw content, detecting format by file extension.

  Falls back to auto-detection if the extension is unrecognized.
  """
  @spec decode_spec_file(binary(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_spec_file(content, file_name) do
    ext = file_name |> Path.extname() |> String.downcase()

    case ext do
      ".json" -> decode_json(content)
      ".yaml" -> decode_yaml(content)
      ".yml" -> decode_yaml(content)
      _ -> auto_detect(content)
    end
  end

  @doc """
  Parses a decoded spec map, validating it as OpenAPI 3.x and extracting key sections.

  Returns a parsed struct with info, servers, paths, security_schemes, and global_security.
  """
  @spec parse(map()) :: {:ok, map()} | {:error, String.t()}
  def parse(raw) do
    cond do
      Map.has_key?(raw, "swagger") ->
        {:error, "Swagger 2.x is not supported. Please convert to OpenAPI 3.0+ first."}

      not Map.has_key?(raw, "openapi") ->
        {:error, "Not a valid OpenAPI specification: missing 'openapi' version field."}

      not supported_version?(raw["openapi"]) ->
        {:error,
         "Unsupported OpenAPI version: #{raw["openapi"]}. Supported versions: 3.0.x, 3.1.x"}

      true ->
        {:ok,
         %{
           openapi_version: raw["openapi"],
           info: raw["info"] || %{},
           servers: raw["servers"] || [],
           paths: raw["paths"] || %{},
           security_schemes: extract_security_schemes(raw),
           global_security: raw["security"] || []
         }}
    end
  end

  @doc """
  Extracts service definitions from a parsed spec.

  One service per unique path. Options:
  - `:upstream_url` — override the upstream URL (default: first server URL)
  """
  @spec extract_services(map(), keyword()) :: [map()]
  def extract_services(parsed, opts \\ []) do
    upstream_override = Keyword.get(opts, :upstream_url)
    server_url = get_server_url(parsed.servers)
    {base_path, upstream_base} = split_server_url(server_url)

    upstream = upstream_override || upstream_base || "http://localhost:8080"

    parsed.paths
    |> Enum.sort_by(fn {path, _} -> path end)
    |> Enum.map(fn {path, path_item} ->
      methods = extract_methods(path_item)
      first_op = first_operation(path_item)
      security_refs = collect_security_refs(path_item, parsed.global_security)

      route = convert_path(base_path <> path)
      name = derive_name(first_op, path)

      %{
        name: name,
        route_path: route,
        upstream_url: upstream,
        description: first_op["summary"] || first_op["description"],
        openapi_path: path,
        methods: methods,
        security_refs: security_refs
      }
    end)
  end

  @doc """
  Extracts auth policy definitions from security schemes in the parsed spec.
  """
  @spec extract_auth_policies(map()) :: [map()]
  def extract_auth_policies(parsed) do
    parsed.security_schemes
    |> Enum.map(fn {scheme_name, scheme} -> map_security_scheme(scheme_name, scheme) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Compares two parsed specs and returns added, removed, and unchanged paths.
  """
  @spec diff_specs(map(), map()) :: %{
          added: [String.t()],
          removed: [String.t()],
          unchanged: [String.t()]
        }
  def diff_specs(old_parsed, new_parsed) do
    old_paths = old_parsed.paths |> Map.keys() |> MapSet.new()
    new_paths = new_parsed.paths |> Map.keys() |> MapSet.new()

    %{
      added: MapSet.difference(new_paths, old_paths) |> MapSet.to_list() |> Enum.sort(),
      removed: MapSet.difference(old_paths, new_paths) |> MapSet.to_list() |> Enum.sort(),
      unchanged: MapSet.intersection(old_paths, new_paths) |> MapSet.to_list() |> Enum.sort()
    }
  end

  # --- Private helpers ---

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "JSON content is not an object"}
      {:error, %Jason.DecodeError{} = err} -> {:error, "Invalid JSON: #{Exception.message(err)}"}
    end
  end

  defp decode_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, _} ->
        {:error, "YAML content is not a mapping"}

      {:error, %YamlElixir.ParsingError{} = err} ->
        {:error, "Invalid YAML: #{Exception.message(err)}"}
    end
  end

  defp auto_detect(content) do
    trimmed = String.trim_leading(content)

    if String.starts_with?(trimmed, "{") do
      decode_json(content)
    else
      decode_yaml(content)
    end
  end

  defp supported_version?(version) when is_binary(version) do
    Enum.any?(@supported_versions, &String.starts_with?(version, &1))
  end

  defp supported_version?(_), do: false

  defp extract_security_schemes(raw) do
    case get_in(raw, ["components", "securitySchemes"]) do
      nil -> %{}
      schemes when is_map(schemes) -> schemes
    end
  end

  defp get_server_url([%{"url" => url} | _]), do: url
  defp get_server_url(_), do: nil

  defp split_server_url(nil), do: {"", nil}

  defp split_server_url(url) do
    uri = URI.parse(url)
    base_path = (uri.path || "") |> String.trim_trailing("/")

    upstream =
      "#{uri.scheme || "http"}://#{uri.host || "localhost"}#{if uri.port && uri.port not in [80, 443], do: ":#{uri.port}", else: ""}"

    {base_path, upstream}
  end

  defp convert_path(path) do
    path
    |> String.replace(~r/\{[^}]+\}/, "*")
    |> ensure_leading_slash()
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  @http_methods ~w(get post put patch delete options head trace)

  defp extract_methods(path_item) do
    path_item
    |> Map.take(@http_methods)
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&String.upcase/1)
  end

  defp first_operation(path_item) do
    @http_methods
    |> Enum.find_value(fn method ->
      case Map.get(path_item, method) do
        nil -> nil
        op when is_map(op) -> op
      end
    end) || %{}
  end

  defp collect_security_refs(path_item, global_security) do
    ops =
      @http_methods
      |> Enum.flat_map(fn method ->
        case Map.get(path_item, method) do
          %{"security" => sec} when is_list(sec) -> sec
          _ -> []
        end
      end)

    refs = if ops == [], do: global_security, else: ops

    refs
    |> List.wrap()
    |> Enum.flat_map(fn
      item when is_map(item) -> Map.keys(item)
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp derive_name(%{"operationId" => op_id}, _path) when is_binary(op_id) and op_id != "" do
    op_id
    |> String.replace(~r/[^a-zA-Z0-9]+/, " ")
    |> String.trim()
  end

  defp derive_name(_, path) do
    path
    |> String.replace(~r/[{}\/]+/, " ")
    |> String.trim()
    |> case do
      "" -> "root"
      name -> name
    end
  end

  defp map_security_scheme(name, %{"type" => "http", "scheme" => "bearer"} = scheme) do
    %{
      name: name,
      auth_type: "jwt",
      config: Map.take(scheme, ["bearerFormat"]),
      description: scheme["description"]
    }
  end

  defp map_security_scheme(name, %{"type" => "http", "scheme" => "basic"} = scheme) do
    %{
      name: name,
      auth_type: "basic",
      config: %{},
      description: scheme["description"]
    }
  end

  defp map_security_scheme(name, %{"type" => "apiKey"} = scheme) do
    %{
      name: name,
      auth_type: "api_key",
      config: %{
        "header_name" => scheme["name"],
        "location" => scheme["in"]
      },
      description: scheme["description"]
    }
  end

  defp map_security_scheme(name, %{"type" => "oauth2"} = scheme) do
    %{
      name: name,
      auth_type: "jwt",
      config: %{"flows" => scheme["flows"]},
      description: scheme["description"]
    }
  end

  defp map_security_scheme(name, %{"type" => "openIdConnect"} = scheme) do
    %{
      name: name,
      auth_type: "jwt",
      config: %{"openid_connect_url" => scheme["openIdConnectUrl"]},
      description: scheme["description"]
    }
  end

  defp map_security_scheme(name, %{"type" => "mutualTLS"} = scheme) do
    %{
      name: name,
      auth_type: "mtls",
      config: %{},
      description: scheme["description"]
    }
  end

  defp map_security_scheme(_name, _scheme), do: nil
end
