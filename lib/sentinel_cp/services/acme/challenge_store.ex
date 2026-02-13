defmodule SentinelCp.Services.Acme.ChallengeStore do
  @moduledoc """
  ETS-backed GenServer for storing ephemeral ACME HTTP-01 challenge tokens.

  Tokens are stored with a TTL and cleaned up periodically.
  """

  use GenServer

  @table :acme_challenge_tokens
  @cleanup_interval :timer.minutes(5)
  @ttl_seconds 600

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a challenge token and its key authorization.
  """
  def put(token, key_authorization) do
    expires_at = System.system_time(:second) + @ttl_seconds
    :ets.insert(@table, {token, key_authorization, expires_at})
    :ok
  end

  @doc """
  Retrieves the key authorization for a challenge token.
  """
  def get(token) do
    case :ets.lookup(@table, token) do
      [{^token, key_auth, expires_at}] ->
        if System.system_time(:second) < expires_at do
          {:ok, key_auth}
        else
          :ets.delete(@table, token)
          :error
        end

      [] ->
        :error
    end
  end

  @doc """
  Removes a challenge token.
  """
  def delete(token) do
    :ets.delete(@table, token)
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
    match_spec = [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}]
    :ets.select_delete(@table, match_spec)
  end
end
