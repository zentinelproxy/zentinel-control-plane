defmodule ZentinelCpWeb.GraphQL.Socket do
  @moduledoc false
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: ZentinelCpWeb.GraphQL.Schema

  alias ZentinelCp.Accounts

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Accounts.get_api_key_by_key(token) do
      nil ->
        :error

      api_key ->
        Accounts.touch_api_key(api_key)

        socket =
          Absinthe.Phoenix.Socket.put_options(socket,
            context: %{current_api_key: api_key}
          )

        {:ok, socket}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket) do
    case socket.assigns[:absinthe] do
      %{opts: [context: %{current_api_key: api_key}]} ->
        "graphql:#{api_key.id}"

      _ ->
        nil
    end
  end
end
