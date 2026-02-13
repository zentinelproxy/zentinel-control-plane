defmodule SentinelCp.Portal do
  @moduledoc """
  The Portal context handles developer portal functionality.

  Provides docs rendering from OpenAPI specs, interactive API console,
  and self-service API key management for portal users.
  """

  alias SentinelCp.{Repo, Accounts}
  alias SentinelCp.Services.OpenApiSpec
  import Ecto.Query, warn: false

  ## Docs rendering

  @doc """
  Lists active OpenAPI specs for a project.
  """
  def list_project_specs(project_id) do
    from(s in OpenApiSpec,
      where: s.project_id == ^project_id and s.status == "active",
      order_by: [desc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets an OpenAPI spec by ID.
  """
  def get_spec(id), do: Repo.get(OpenApiSpec, id)

  @doc """
  Extracts paths from an OpenAPI spec for documentation rendering.

  Returns a list of `%{path, method, summary, description, parameters, request_body, responses, tags}`.
  """
  def get_spec_paths(%OpenApiSpec{spec_data: spec_data}) when is_map(spec_data) do
    paths = Map.get(spec_data, "paths", %{})

    paths
    |> Enum.flat_map(fn {path, methods} ->
      methods
      |> Enum.filter(fn {method, _} -> method in ~w(get post put patch delete options head) end)
      |> Enum.map(fn {method, details} ->
        %{
          path: path,
          method: String.upcase(method),
          summary: Map.get(details, "summary", ""),
          description: Map.get(details, "description", ""),
          parameters: Map.get(details, "parameters", []),
          request_body: Map.get(details, "requestBody"),
          responses: Map.get(details, "responses", %{}),
          tags: Map.get(details, "tags", [])
        }
      end)
    end)
    |> Enum.sort_by(fn ep -> {ep.path, method_order(ep.method)} end)
  end

  def get_spec_paths(_), do: []

  @doc """
  Extracts schema definitions from an OpenAPI spec.
  """
  def get_spec_schemas(%OpenApiSpec{spec_data: spec_data}) when is_map(spec_data) do
    components = Map.get(spec_data, "components", %{})
    Map.get(components, "schemas", %{})
  end

  def get_spec_schemas(_), do: %{}

  @doc """
  Groups spec paths by their first tag.
  """
  def group_paths_by_tag(paths) do
    paths
    |> Enum.group_by(fn ep ->
      case ep.tags do
        [tag | _] -> tag
        _ -> "Other"
      end
    end)
    |> Enum.sort_by(fn {tag, _} -> tag end)
  end

  ## Console

  @doc """
  Executes an HTTP request via the API console.

  Returns `{:ok, %{status, headers, body, duration_ms}}` or `{:error, reason}`.
  """
  def execute_request(method, url, headers \\ [], body \\ nil) do
    start_time = System.monotonic_time(:millisecond)

    req_headers =
      headers
      |> Enum.reject(fn {k, v} -> k == "" or v == "" end)
      |> Enum.map(fn {k, v} -> {k, v} end)

    req_opts = [
      method: parse_method(method),
      url: url,
      headers: req_headers,
      receive_timeout: 30_000
    ]

    req_opts =
      if body && body != "" do
        Keyword.put(req_opts, :body, body)
      else
        req_opts
      end

    case Req.request(req_opts) do
      {:ok, response} ->
        duration = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           status: response.status,
           headers: format_response_headers(response.headers),
           body: format_response_body(response.body),
           duration_ms: duration
         }}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Connection failed: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Builds a curl command string for display purposes.
  """
  def build_curl_command(method, url, headers \\ [], body \\ nil) do
    parts = ["curl -X #{String.upcase(method)}"]

    header_parts =
      headers
      |> Enum.reject(fn {k, v} -> k == "" or v == "" end)
      |> Enum.map(fn {k, v} -> "-H '#{k}: #{v}'" end)

    body_part =
      if body && body != "" do
        ["-d '#{body}'"]
      else
        []
      end

    (parts ++ header_parts ++ body_part ++ ["'#{url}'"])
    |> Enum.join(" \\\n  ")
  end

  ## Key self-service

  @doc """
  Creates a portal API key scoped to read-only access for a project.
  """
  def create_portal_key(project_id, name, user_id) do
    Accounts.create_api_key(%{
      name: "portal-#{name}",
      user_id: user_id,
      project_id: project_id,
      scopes: ["services:read", "bundles:read"]
    })
  end

  @doc """
  Lists portal API keys for a user within a project.
  """
  def list_portal_keys(project_id, user_id) do
    from(k in SentinelCp.Accounts.ApiKey,
      where: k.project_id == ^project_id and k.user_id == ^user_id,
      where: is_nil(k.revoked_at),
      order_by: [desc: k.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Revokes a portal API key.
  """
  def revoke_portal_key(key_id, user_id) do
    case Repo.get(SentinelCp.Accounts.ApiKey, key_id) do
      nil ->
        {:error, :not_found}

      %{user_id: ^user_id} = key ->
        Accounts.revoke_api_key(key)

      _ ->
        {:error, :not_authorized}
    end
  end

  ## Private

  defp parse_method(method) when is_binary(method) do
    method |> String.downcase() |> String.to_existing_atom()
  rescue
    _ -> :get
  end

  defp method_order("GET"), do: 0
  defp method_order("POST"), do: 1
  defp method_order("PUT"), do: 2
  defp method_order("PATCH"), do: 3
  defp method_order("DELETE"), do: 4
  defp method_order(_), do: 5

  defp format_response_headers(headers) do
    Enum.map(headers, fn {k, v} ->
      value = if is_list(v), do: Enum.join(v, ", "), else: to_string(v)
      {to_string(k), value}
    end)
  end

  defp format_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp format_response_body(body) when is_map(body) do
    Jason.encode!(body, pretty: true)
  end

  defp format_response_body(body), do: inspect(body)
end
