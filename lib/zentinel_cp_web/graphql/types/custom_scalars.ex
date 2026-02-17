defmodule ZentinelCpWeb.GraphQL.Types.CustomScalars do
  @moduledoc false
  use Absinthe.Schema.Notation

  scalar :datetime, name: "DateTime" do
    serialize(fn
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
      other -> to_string(other)
    end)

    parse(fn
      %Absinthe.Blueprint.Input.String{value: value} ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} -> {:ok, dt}
          _ -> :error
        end

      _ ->
        :error
    end)
  end

  scalar :json, name: "JSON" do
    serialize(fn value -> value end)

    parse(fn
      %Absinthe.Blueprint.Input.String{value: value} ->
        case Jason.decode(value) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> :error
        end

      %Absinthe.Blueprint.Input.Object{} = object ->
        {:ok, decode_object(object)}

      _ ->
        :error
    end)
  end

  defp decode_object(%Absinthe.Blueprint.Input.Object{fields: fields}) do
    Map.new(fields, fn %Absinthe.Blueprint.Input.Field{name: name, input_value: input} ->
      {name, decode_value(input)}
    end)
  end

  defp decode_value(%Absinthe.Blueprint.Input.Value{normalized: normalized}) do
    decode_normalized(normalized)
  end

  defp decode_value(other), do: other

  defp decode_normalized(%Absinthe.Blueprint.Input.String{value: value}), do: value
  defp decode_normalized(%Absinthe.Blueprint.Input.Integer{value: value}), do: value
  defp decode_normalized(%Absinthe.Blueprint.Input.Float{value: value}), do: value
  defp decode_normalized(%Absinthe.Blueprint.Input.Boolean{value: value}), do: value
  defp decode_normalized(%Absinthe.Blueprint.Input.Null{}), do: nil
  defp decode_normalized(%Absinthe.Blueprint.Input.Object{} = obj), do: decode_object(obj)

  defp decode_normalized(%Absinthe.Blueprint.Input.List{items: items}),
    do: Enum.map(items, &decode_value/1)

  defp decode_normalized(other), do: other
end
