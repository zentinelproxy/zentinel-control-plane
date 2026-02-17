defmodule ZentinelCpWeb.HealthController do
  @moduledoc """
  Health and readiness endpoints for liveness/readiness probes.
  """
  use ZentinelCpWeb, :controller

  @doc """
  GET /health — Liveness probe. Always returns 200.
  """
  def health(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  @doc """
  GET /ready — Readiness probe. Checks DB connectivity.
  """
  def ready(conn, _params) do
    case check_db() do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "unavailable", reason: reason})
    end
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(ZentinelCp.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "database unavailable"}
    end
  rescue
    _ -> {:error, "database unavailable"}
  end
end
