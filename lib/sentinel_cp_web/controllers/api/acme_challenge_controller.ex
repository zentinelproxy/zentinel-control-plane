defmodule SentinelCpWeb.Api.AcmeChallengeController do
  @moduledoc """
  Serves ACME HTTP-01 challenge responses.

  Responds to requests at `/.well-known/acme-challenge/:token`
  with the corresponding key authorization from the ChallengeStore.
  """

  use SentinelCpWeb, :controller

  alias SentinelCp.Services.Acme.ChallengeStore

  def show(conn, %{"token" => token}) do
    case ChallengeStore.get(token) do
      {:ok, key_authorization} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, key_authorization)

      :error ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Challenge not found")
    end
  end
end
