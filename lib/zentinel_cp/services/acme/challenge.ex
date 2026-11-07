defmodule ZentinelCp.Services.Acme.Challenge do
  @moduledoc """
  A pending ACME HTTP-01 challenge. Stored in the database because the ACME
  server's request can reach any instance behind the load balancer.
  """
  use Ecto.Schema

  @primary_key {:token, :string, autogenerate: false}

  schema "acme_challenges" do
    field :key_authorization, :string
    field :expires_at, :utc_datetime
  end
end
