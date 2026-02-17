defmodule ZentinelCp.Services.IssuedCertificateExpiryWorker do
  @moduledoc """
  Oban worker that checks for expired issued certificates.

  Runs daily and marks issued certificates past their not_after date as "expired".
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  import Ecto.Query
  alias ZentinelCp.Repo
  alias ZentinelCp.Services.IssuedCertificate

  @check_interval_seconds 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    {expired_count, _} =
      from(c in IssuedCertificate,
        where: c.status == "active",
        where: c.not_after <= ^now
      )
      |> Repo.update_all(set: [status: "expired"])

    if expired_count > 0 do
      Logger.warning(
        "IssuedCertificateExpiryWorker: marked #{expired_count} issued certificates as expired"
      )
    end

    schedule_next()
    :ok
  end

  @doc """
  Ensures the expiry worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 60) |> Oban.insert()
    end
  end

  defp schedule_next do
    %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
  end
end
