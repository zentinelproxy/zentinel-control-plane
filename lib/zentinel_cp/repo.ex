defmodule ZentinelCp.Repo do
  use Ecto.Repo,
    otp_app: :zentinel_cp,
    adapter: Application.compile_env(:zentinel_cp, :ecto_adapter, Ecto.Adapters.SQLite3)
end
