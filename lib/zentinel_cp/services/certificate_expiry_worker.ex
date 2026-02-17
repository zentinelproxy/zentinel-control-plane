defmodule ZentinelCp.Services.CertificateExpiryWorker do
  @moduledoc """
  Oban worker that checks for expiring and expired certificates.

  Runs daily and updates certificate statuses:
  - Certificates expiring within 30 days → "expiring_soon"
  - Certificates past their not_after date → "expired"
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  import Ecto.Query
  alias ZentinelCp.Repo
  alias ZentinelCp.Services.Certificate

  @check_interval_seconds 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    expiry_threshold = DateTime.add(now, 30 * 86_400, :second)

    # Mark expired certificates
    {expired_count, _} =
      from(c in Certificate,
        where: c.status in ["active", "expiring_soon"],
        where: c.not_after <= ^now
      )
      |> Repo.update_all(set: [status: "expired"])

    if expired_count > 0 do
      Logger.warning("CertificateExpiryWorker: marked #{expired_count} certificates as expired")
    end

    # Mark expiring soon certificates
    {expiring_count, _} =
      from(c in Certificate,
        where: c.status == "active",
        where: c.not_after > ^now,
        where: c.not_after <= ^expiry_threshold
      )
      |> Repo.update_all(set: [status: "expiring_soon"])

    if expiring_count > 0 do
      Logger.info(
        "CertificateExpiryWorker: marked #{expiring_count} certificates as expiring_soon"
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
