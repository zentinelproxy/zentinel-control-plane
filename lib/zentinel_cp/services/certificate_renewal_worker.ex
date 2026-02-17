defmodule ZentinelCp.Services.CertificateRenewalWorker do
  @moduledoc """
  Oban worker that checks for certificates eligible for ACME auto-renewal.

  Runs every 6 hours. Queries certificates with `auto_renew: true`,
  non-empty `acme_config`, and approaching expiry (within configured
  threshold days, default 30). Calls `Renewal.renew/1` for each.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  alias ZentinelCp.{Audit, Services}
  alias ZentinelCp.Services.Acme.Renewal

  @check_interval_seconds 21_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    candidates = Services.list_acme_renewal_candidates()

    if candidates != [] do
      Logger.info("CertificateRenewalWorker: found #{length(candidates)} renewal candidates")
    end

    for cert <- candidates do
      case Renewal.renew(cert) do
        {:ok, _updated} ->
          Logger.info("CertificateRenewalWorker: renewed #{cert.domain} (#{cert.id})")

          Audit.log_system_action("renew", "certificate", cert.id,
            project_id: cert.project_id,
            metadata: %{method: "acme", domain: cert.domain}
          )

        {:error, reason} ->
          Logger.error(
            "CertificateRenewalWorker: failed to renew #{cert.domain} (#{cert.id}): #{inspect(reason)}"
          )

          Audit.log_system_action("renew_failed", "certificate", cert.id,
            project_id: cert.project_id,
            metadata: %{method: "acme", domain: cert.domain, error: inspect(reason)}
          )
      end
    end

    schedule_next()
    :ok
  end

  @doc """
  Ensures the renewal worker is scheduled. Safe to call multiple times.
  """
  def ensure_started do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: 120) |> Oban.insert()
    end
  end

  defp schedule_next do
    oban_config = Application.get_env(:zentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{} |> __MODULE__.new(schedule_in: @check_interval_seconds) |> Oban.insert()
    end
  end
end
