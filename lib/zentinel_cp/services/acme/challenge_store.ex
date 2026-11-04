defmodule ZentinelCp.Services.Acme.ChallengeStore do
  @moduledoc """
  Stores ephemeral ACME HTTP-01 challenge tokens in the database, shared by all
  instances. Tokens expire after a TTL and are cleaned up periodically.
  """

  use GenServer

  import Ecto.Query

  alias ZentinelCp.Repo
  alias ZentinelCp.Services.Acme.Challenge

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
    expires_at = DateTime.utc_now() |> DateTime.add(@ttl_seconds) |> DateTime.truncate(:second)

    Repo.insert!(
      %Challenge{token: token, key_authorization: key_authorization, expires_at: expires_at},
      on_conflict: {:replace, [:key_authorization, :expires_at]},
      conflict_target: :token
    )

    :ok
  end

  @doc """
  Retrieves the key authorization for a challenge token.
  """
  def get(token) do
    now = DateTime.utc_now()

    case Repo.one(from(c in Challenge, where: c.token == ^token and c.expires_at > ^now)) do
      %Challenge{key_authorization: key_authorization} -> {:ok, key_authorization}
      nil -> :error
    end
  end

  @doc """
  Removes a challenge token.
  """
  def delete(token) do
    Repo.delete_all(from(c in Challenge, where: c.token == ^token))
    :ok
  end

  ## Server

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    # A failed cleanup is retried on the next interval; expired rows are ignored by get/1.
    try do
      Repo.delete_all(from(c in Challenge, where: c.expires_at <= ^now))
    rescue
      error in [DBConnection.ConnectionError, DBConnection.OwnershipError, Postgrex.Error] ->
        require Logger
        Logger.warning("ACME challenge cleanup failed: #{Exception.message(error)}")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
