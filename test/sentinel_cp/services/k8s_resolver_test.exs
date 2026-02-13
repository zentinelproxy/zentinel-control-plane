defmodule SentinelCp.Services.K8sResolverTest do
  use ExUnit.Case, async: true

  alias SentinelCp.Services.K8sResolver.HTTP

  describe "parse_endpoints/2" do
    test "parses multiple subsets with addresses and ports" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"},
              %{"ip" => "10.0.0.2"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"}
            ]
          },
          %{
            "addresses" => [
              %{"ip" => "10.0.1.1"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 9090, "protocol" => "TCP"}
            ]
          }
        ]
      }

      result = HTTP.parse_endpoints(body)

      assert length(result) == 3
      assert {0, 1, 8080, ~c"10.0.0.1"} in result
      assert {0, 1, 8080, ~c"10.0.0.2"} in result
      assert {0, 1, 9090, ~c"10.0.1.1"} in result
    end

    test "filters ports by port_name" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"},
              %{"name" => "grpc", "port" => 9090, "protocol" => "TCP"}
            ]
          }
        ]
      }

      result = HTTP.parse_endpoints(body, "http")

      assert result == [{0, 1, 8080, ~c"10.0.0.1"}]
    end

    test "returns all ports when port_name is nil" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"},
              %{"name" => "grpc", "port" => 9090, "protocol" => "TCP"}
            ]
          }
        ]
      }

      result = HTTP.parse_endpoints(body, nil)

      assert length(result) == 2
      assert {0, 1, 8080, ~c"10.0.0.1"} in result
      assert {0, 1, 9090, ~c"10.0.0.1"} in result
    end

    test "falls back to all ports when port_name not found" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"}
            ]
          }
        ]
      }

      result = HTTP.parse_endpoints(body, "nonexistent")

      assert result == [{0, 1, 8080, ~c"10.0.0.1"}]
    end

    test "handles empty subsets" do
      assert HTTP.parse_endpoints(%{"subsets" => []}) == []
    end

    test "handles missing subsets key" do
      assert HTTP.parse_endpoints(%{}) == []
    end

    test "handles subset with no addresses" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"}
            ]
          }
        ]
      }

      assert HTTP.parse_endpoints(body) == []
    end

    test "handles subset with no ports" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"}
            ],
            "ports" => []
          }
        ]
      }

      assert HTTP.parse_endpoints(body) == []
    end

    test "multiple addresses × multiple ports produces cartesian product" do
      body = %{
        "subsets" => [
          %{
            "addresses" => [
              %{"ip" => "10.0.0.1"},
              %{"ip" => "10.0.0.2"}
            ],
            "ports" => [
              %{"name" => "http", "port" => 8080, "protocol" => "TCP"},
              %{"name" => "grpc", "port" => 9090, "protocol" => "TCP"}
            ]
          }
        ]
      }

      result = HTTP.parse_endpoints(body)

      assert length(result) == 4
      assert {0, 1, 8080, ~c"10.0.0.1"} in result
      assert {0, 1, 9090, ~c"10.0.0.1"} in result
      assert {0, 1, 8080, ~c"10.0.0.2"} in result
      assert {0, 1, 9090, ~c"10.0.0.2"} in result
    end
  end
end
