defmodule ZentinelCpWeb.Plugs.ValidatePathIds do
  @moduledoc """
  Answers 404 when an ID in the URL path is not a UUID. PostgreSQL's UUID columns
  reject such values with an exception, while no such record can exist anyway.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Enum.all?(conn.path_params, &valid_param?/1) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{error: "Not found"}))
      |> halt()
    end
  end

  defp valid_param?({name, value})
       when name == "id" or binary_part(name, byte_size(name), -3) == "_id" do
    match?({:ok, _}, Ecto.UUID.cast(value))
  end

  defp valid_param?(_param), do: true
end
