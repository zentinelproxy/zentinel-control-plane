defmodule ZentinelCp.Services.ConsulResolver.HTTP do
  @moduledoc """
  Consul Catalog API resolver using Req.

  Calls `GET {consul_addr}/v1/catalog/service/{service_name}` and parses
  the response into SRV-compatible tuples for service discovery.

  Supports optional datacenter, tag filtering, and ACL token authentication.

  `consul_addr` is checked with `ZentinelCp.Net.UrlGuard` (`:no_local`) and may
  not carry a query or fragment, redirects are not followed, and a failed
  response is reported by its status only, so the error a tenant sees does not
  carry what another server answered.
  """

  @behaviour ZentinelCp.Services.ConsulResolver

  alias ZentinelCp.Net.UrlGuard

  @impl true
  def resolve_service(config) do
    consul_addr = config["consul_addr"]
    service_name = config["service_name"]

    with {:ok, url} <- build_url(consul_addr, service_name, config),
         :ok <- check_url(url) do
      headers = build_headers(config)

      case Req.get(url, headers: headers, redirect: false, retry: false) do
        {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
          {:ok, parse_catalog_response(body)}

        {:ok, %Req.Response{status: 200}} ->
          {:error, "Consul API returned a body that is not a list of service entries"}

        {:ok, %Req.Response{status: status}} ->
          {:error, "Consul API returned #{status}"}

        {:error, reason} ->
          {:error, "Consul API request failed: #{inspect(reason)}"}
      end
    end
  end

  defp check_url(url) do
    case UrlGuard.check(url, :no_local) do
      :ok -> :ok
      {:error, reason} -> {:error, "Consul address is not allowed: #{reason}"}
    end
  end

  @doc """
  Parses a Consul Catalog service response into SRV-compatible tuples.

  Returns `{0, weight, port, ip_charlist}` for each service entry.
  Weight is taken from `ServiceWeights.Passing` (default 1).
  """
  def parse_catalog_response(entries) do
    Enum.map(entries, fn entry ->
      ip = entry["ServiceAddress"]
      ip = if ip == "" or is_nil(ip), do: entry["Address"], else: ip
      port = entry["ServicePort"] || 0

      weight =
        case entry["ServiceWeights"] do
          %{"Passing" => w} when is_integer(w) and w > 0 -> w
          _ -> 1
        end

      {0, weight, port, to_charlist(ip || "127.0.0.1")}
    end)
  end

  defp build_url(consul_addr, service_name, config)
       when is_binary(consul_addr) and is_binary(service_name) and service_name != "" do
    case URI.parse(consul_addr) do
      %URI{query: nil, fragment: nil} ->
        {:ok, catalog_url(consul_addr, service_name, config)}

      _ ->
        {:error, "Consul address must not contain a query or fragment"}
    end
  end

  defp build_url(_consul_addr, _service_name, _config),
    do: {:error, "Consul address and service name are required"}

  defp catalog_url(consul_addr, service_name, config) do
    base = String.trim_trailing(consul_addr, "/")
    url = "#{base}/v1/catalog/service/#{URI.encode(service_name, &URI.char_unreserved?/1)}"

    params =
      []
      |> maybe_add_param("dc", config["datacenter"])
      |> maybe_add_param("tag", config["tag"])

    case params do
      [] -> url
      _ -> url <> "?" <> URI.encode_query(params)
    end
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, key, value), do: params ++ [{key, value}]

  defp build_headers(config) do
    case config["token"] do
      token when is_binary(token) and token != "" ->
        [{"X-Consul-Token", token}]

      _ ->
        []
    end
  end
end
