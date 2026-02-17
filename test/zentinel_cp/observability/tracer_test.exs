defmodule ZentinelCp.Observability.TracerTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Observability.Tracer

  describe "span/3" do
    test "executes function and returns result" do
      result = Tracer.span(:test_span, %{key: "value"}, fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "re-raises exceptions" do
      assert_raise RuntimeError, "boom", fn ->
        Tracer.span(:test_span, %{}, fn -> raise "boom" end)
      end
    end
  end

  describe "helper functions" do
    test "trace_compilation returns wrapped result" do
      assert Tracer.trace_compilation("bundle-123", fn -> :compiled end) == :compiled
    end

    test "trace_rollout_tick returns wrapped result" do
      assert Tracer.trace_rollout_tick("rollout-456", fn -> {:ok, :step_started} end) ==
               {:ok, :step_started}
    end

    test "trace_webhook returns wrapped result" do
      assert Tracer.trace_webhook("github", fn -> :processed end) == :processed
    end

    test "trace_heartbeat returns wrapped result" do
      assert Tracer.trace_heartbeat("node-789", fn -> {:ok, :recorded} end) ==
               {:ok, :recorded}
    end
  end
end
