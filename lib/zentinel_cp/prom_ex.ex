defmodule ZentinelCp.PromEx do
  @moduledoc """
  PromEx configuration for Prometheus metrics.

  Provides out-of-the-box metrics for Phoenix, Ecto, Oban, and BEAM,
  plus custom Zentinel-specific application metrics.
  """
  use PromEx, otp_app: :zentinel_cp

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: ZentinelCpWeb.Router, endpoint: ZentinelCpWeb.Endpoint},
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      ZentinelCp.PromEx.ZentinelPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "zentinel-cp",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
