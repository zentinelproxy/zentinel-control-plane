defmodule ZentinelCp.RateLimit do
  @moduledoc """
  ETS-backed token bucket rate limiter for API endpoints.

  Supports per-API-key, per-IP, and per-scope rate limits with
  configurable bucket sizes and refill rates. Cost-aware limits
  allow expensive operations (e.g., compilation) to consume more tokens.
  """

  use GenServer

  @table :zentinel_rate_limits
  @cleanup_interval :timer.minutes(5)

  # Default limits per minute
  @default_limits %{
    "nodes:read" => 1000,
    "nodes:write" => 200,
    "bundles:read" => 500,
    "bundles:write" => 100,
    "rollouts:read" => 500,
    "rollouts:write" => 100,
    "services:read" => 500,
    "services:write" => 200,
    "api_keys:admin" => 50,
    "default" => 300
  }

  # Cost multipliers for expensive operations
  @cost_multipliers %{
    "bundles:compile" => 10,
    "bundles:create" => 5,
    "rollouts:create" => 3
  }

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a request is allowed under rate limits.

  Returns `{:allow, remaining, limit, reset_at}` or `{:deny, limit, reset_at}`.

  ## Parameters
    - `key` - Rate limit key (e.g., API key ID or IP address)
    - `scope` - The API scope being accessed
    - `opts` - Options:
      - `:cost` - Number of tokens to consume (default 1)
      - `:action` - Action name for cost multiplier lookup
  """
  def check_rate(key, scope, opts \\ []) do
    cost = resolve_cost(opts)
    limit = get_limit(scope)
    now = System.system_time(:second)
    window_start = div(now, 60) * 60
    reset_at = window_start + 60

    bucket_key = {key, scope, window_start}

    case :ets.lookup(@table, bucket_key) do
      [{_, count}] ->
        new_count = count + cost

        if new_count <= limit do
          :ets.update_counter(@table, bucket_key, {2, cost})
          {:allow, limit - new_count, limit, reset_at}
        else
          {:deny, limit, reset_at}
        end

      [] ->
        :ets.insert(@table, {bucket_key, cost})
        {:allow, limit - cost, limit, reset_at}
    end
  end

  @doc """
  Gets the configured rate limit for a scope.
  """
  def get_limit(scope) do
    configured = Application.get_env(:zentinel_cp, :rate_limits, %{})
    Map.get(configured, scope) || Map.get(@default_limits, scope) || @default_limits["default"]
  end

  @doc """
  Returns the current usage count for a key/scope in the current window.
  """
  def current_usage(key, scope) do
    now = System.system_time(:second)
    window_start = div(now, 60) * 60
    bucket_key = {key, scope, window_start}

    case :ets.lookup(@table, bucket_key) do
      [{_, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Resets rate limit counters for a key. Used in testing.
  """
  def reset(key) do
    match_spec = [{{{key, :_, :_}, :_}, [], [true]}]
    :ets.select_delete(@table, match_spec)
    :ok
  end

  @doc """
  Resets all rate limit counters. Used in testing.
  """
  def reset_all do
    :ets.delete_all_objects(@table)
    :ok
  end

  ## Server

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired do
    now = System.system_time(:second)
    # Remove entries from windows older than 2 minutes ago
    cutoff = div(now, 60) * 60 - 120

    match_spec = [{{:{}, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}]
    :ets.select_delete(@table, match_spec)
  end

  defp resolve_cost(opts) do
    base_cost = Keyword.get(opts, :cost, 1)
    action = Keyword.get(opts, :action)

    multiplier = if action, do: Map.get(@cost_multipliers, action, 1), else: 1
    base_cost * multiplier
  end
end
