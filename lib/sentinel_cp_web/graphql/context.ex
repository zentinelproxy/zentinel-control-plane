defmodule SentinelCpWeb.GraphQL.Context do
  @moduledoc """
  Plug that transfers conn assigns into the Absinthe context.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    context = %{current_api_key: conn.assigns[:current_api_key]}
    Absinthe.Plug.put_options(conn, context: context)
  end
end
