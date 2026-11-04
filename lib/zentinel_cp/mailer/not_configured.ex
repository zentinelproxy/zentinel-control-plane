defmodule ZentinelCp.Mailer.NotConfigured do
  @moduledoc """
  Swoosh adapter for deployments with no email provider. Delivery returns an
  error, so email channels show a failed delivery rather than silently losing it.
  """
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :mailer_not_configured}
end
