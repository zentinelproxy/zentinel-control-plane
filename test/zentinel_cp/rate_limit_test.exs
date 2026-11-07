defmodule ZentinelCp.RateLimitTest do
  @configured_limits Application.compile_env(:zentinel_cp, :rate_limits, %{})

  use ExUnit.Case, async: false

  alias ZentinelCp.RateLimit

  setup do
    # Ensure the GenServer is running (started by application)
    # Clean up between tests
    RateLimit.reset_all()
    :ok
  end

  # Other tests rely on the limits in config/test.exs, so they are restored, not deleted.
  defp put_limits(limits) do
    Application.put_env(:zentinel_cp, :rate_limits, Map.merge(@configured_limits, limits))
  end

  defp restore_limits, do: Application.put_env(:zentinel_cp, :rate_limits, @configured_limits)

  describe "check_rate/3" do
    test "allows requests under the limit" do
      assert {:allow, remaining, limit, _reset} = RateLimit.check_rate("test-key", "default")
      assert remaining > 0
      assert limit > 0
    end

    test "tracks usage per key" do
      RateLimit.check_rate("key-1", "default")
      RateLimit.check_rate("key-1", "default")
      RateLimit.check_rate("key-1", "default")

      assert RateLimit.current_usage("key-1", "default") == 3
      assert RateLimit.current_usage("key-2", "default") == 0
    end

    test "tracks usage per scope" do
      RateLimit.check_rate("key-1", "nodes:read")
      RateLimit.check_rate("key-1", "bundles:read")

      assert RateLimit.current_usage("key-1", "nodes:read") == 1
      assert RateLimit.current_usage("key-1", "bundles:read") == 1
    end

    test "denies requests over the limit" do
      # Set a very low limit for testing
      put_limits(%{"test_scope" => 3})

      assert {:allow, 2, 3, _} = RateLimit.check_rate("deny-key", "test_scope")
      assert {:allow, 1, 3, _} = RateLimit.check_rate("deny-key", "test_scope")
      assert {:allow, 0, 3, _} = RateLimit.check_rate("deny-key", "test_scope")
      assert {:deny, 3, _reset} = RateLimit.check_rate("deny-key", "test_scope")

      # Clean up
      restore_limits()
    end

    test "returns correct remaining count" do
      put_limits(%{"count_scope" => 5})

      assert {:allow, 4, 5, _} = RateLimit.check_rate("count-key", "count_scope")
      assert {:allow, 3, 5, _} = RateLimit.check_rate("count-key", "count_scope")
      assert {:allow, 2, 5, _} = RateLimit.check_rate("count-key", "count_scope")

      restore_limits()
    end

    test "applies cost multipliers" do
      put_limits(%{"bundles:write" => 10})

      # Compilation costs 10x via the action multiplier
      assert {:allow, _, 10, _} =
               RateLimit.check_rate("cost-key", "bundles:write", action: "bundles:compile")

      assert RateLimit.current_usage("cost-key", "bundles:write") == 10

      # Should be denied now (10/10 used)
      assert {:deny, _, _} =
               RateLimit.check_rate("cost-key", "bundles:write", action: "bundles:compile")

      restore_limits()
    end

    test "returns reset timestamp in the future" do
      {:allow, _, _, reset_at} = RateLimit.check_rate("time-key", "default")
      assert reset_at > System.system_time(:second)
    end
  end

  describe "get_limit/1" do
    test "returns configured limits for known scopes" do
      assert RateLimit.get_limit("nodes:read") == 1000
      assert RateLimit.get_limit("bundles:write") == 100
      assert RateLimit.get_limit("rollouts:write") == 100
    end

    test "returns default limit for unknown scopes" do
      assert RateLimit.get_limit("unknown:scope") == 300
    end

    test "prefers application config over defaults" do
      put_limits(%{"nodes:read" => 5000})
      assert RateLimit.get_limit("nodes:read") == 5000
      restore_limits()
    end
  end

  describe "reset/1" do
    test "clears rate limit counters for a key" do
      RateLimit.check_rate("reset-key", "default")
      RateLimit.check_rate("reset-key", "nodes:read")
      assert RateLimit.current_usage("reset-key", "default") > 0

      RateLimit.reset("reset-key")
      assert RateLimit.current_usage("reset-key", "default") == 0
      assert RateLimit.current_usage("reset-key", "nodes:read") == 0
    end
  end
end
