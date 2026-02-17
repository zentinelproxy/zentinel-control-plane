defmodule ZentinelCp.Services.ConsulResolver.HTTP do
  @moduledoc """
  Consul Catalog API resolver using Req.

  Calls `GET {consul_addr}/v1/catalog/service/{service_name}` and parses
  the response into SRV-compatible tuples for service discovery.

  Supports optional datacenter, tag filtering, and ACL token authentication.
  """

  @behaviour ZentinelCp.Services.ConsulResolver

  @impl true
  def resolve_service(config) do
    consul_addr = config["consul_addr"]
    service_name = config["service_name"]

    url = build_url(consul_addr, service_name, config)
    headers = build_headers(config)

    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, parse_catalog_response(body)}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, "Consul API returned unexpected body format: #{inspect(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        message = if is_binary(body), do: body, else: inspect(body)
        {:error, "Consul API returned #{status}: #{message}"}

      {:error, reason} ->
        {:error, "Consul API request failed: #{inspect(reason)}"}
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

  defp build_url(consul_addr, service_name, config) do
    base = String.trim_trailing(consul_addr, "/")
    url = "#{base}/v1/catalog/service/#{URI.encode(service_name)}"

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
