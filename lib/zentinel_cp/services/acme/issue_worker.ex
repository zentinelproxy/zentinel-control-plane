defmodule ZentinelCp.Services.Acme.IssueWorker do
  @moduledoc """
  Oban worker that issues a newly requested ACME certificate. As a job it is
  retried, and it survives a restart of the instance that accepted the request.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias ZentinelCp.Services
  alias ZentinelCp.Services.Acme.Renewal

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"certificate_id" => certificate_id}}) do
    case Services.get_certificate(certificate_id) do
      nil ->
        :ok

      certificate ->
        case Renewal.renew(certificate) do
          {:error, reason} -> {:error, reason}
          _ -> :ok
        end
    end
  end
end
