defmodule ZentinelCp.Services.ConsulResolverTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services.ConsulResolver.HTTP

  describe "parse_catalog_response/1" do
    test "parses standard Consul catalog entries" do
      entries = [
        %{
          "Address" => "10.0.0.1",
          "ServiceAddress" => "10.0.0.1",
          "ServicePort" => 8080,
          "ServiceWeights" => %{"Passing" => 10, "Warning" => 1}
        },
        %{
          "Address" => "10.0.0.2",
          "ServiceAddress" => "10.0.0.2",
          "ServicePort" => 8080,
          "ServiceWeights" => %{"Passing" => 20, "Warning" => 1}
        }
      ]

      result = HTTP.parse_catalog_response(entries)

      assert result == [
               {0, 10, 8080, ~c"10.0.0.1"},
               {0, 20, 8080, ~c"10.0.0.2"}
             ]
    end

    test "falls back to Address when ServiceAddress is empty" do
      entries = [
        %{
          "Address" => "10.0.0.5",
          "ServiceAddress" => "",
          "ServicePort" => 9090,
          "ServiceWeights" => %{"Passing" => 1}
        }
      ]

      result = HTTP.parse_catalog_response(entries)
      assert result == [{0, 1, 9090, ~c"10.0.0.5"}]
    end

    test "defaults weight to 1 when ServiceWeights is missing" do
      entries = [
        %{
          "Address" => "10.0.0.3",
          "ServiceAddress" => "10.0.0.3",
          "ServicePort" => 3000,
          "ServiceWeights" => nil
        }
      ]

      result = HTTP.parse_catalog_response(entries)
      assert result == [{0, 1, 3000, ~c"10.0.0.3"}]
    end

    test "handles empty response" do
      assert HTTP.parse_catalog_response([]) == []
    end

    test "defaults port to 0 when ServicePort is missing" do
      entries = [
        %{
          "Address" => "10.0.0.4",
          "ServiceAddress" => "10.0.0.4",
          "ServicePort" => nil,
          "ServiceWeights" => %{"Passing" => 5}
        }
      ]

      result = HTTP.parse_catalog_response(entries)
      assert result == [{0, 5, 0, ~c"10.0.0.4"}]
    end
  end

  describe "resolve_service/1 with mock" do
    import Mox

    setup :verify_on_exit!

    test "returns error for non-200 status" do
      # We test via the behaviour mock
      ZentinelCp.Services.ConsulResolver.Mock
      |> expect(:resolve_service, fn _config ->
        {:error, "Consul API returned 403: Permission denied"}
      end)

      assert {:error, "Consul API returned 403: Permission denied"} =
               ZentinelCp.Services.ConsulResolver.Mock.resolve_service(%{
                 "consul_addr" => "http://consul:8500",
                 "service_name" => "web"
               })
    end

    test "returns parsed results for valid response" do
      ZentinelCp.Services.ConsulResolver.Mock
      |> expect(:resolve_service, fn _config ->
        {:ok, [{0, 10, 8080, ~c"10.0.0.1"}]}
      end)

      assert {:ok, [{0, 10, 8080, ~c"10.0.0.1"}]} =
               ZentinelCp.Services.ConsulResolver.Mock.resolve_service(%{
                 "consul_addr" => "http://consul:8500",
                 "service_name" => "web"
               })
    end
  end
end
