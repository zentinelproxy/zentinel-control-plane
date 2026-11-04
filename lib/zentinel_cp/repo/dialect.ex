defmodule ZentinelCp.Repo.Dialect do
  @moduledoc """
  Query fragments that differ between PostgreSQL (production) and SQLite
  (development and default tests).

  The adapter is chosen at compile time, so these macros expand to the
  fragment for the compiled adapter. Import this module and use them inside
  Ecto query expressions.
  """

  @postgres Application.compile_env(:zentinel_cp, :ecto_adapter, Ecto.Adapters.SQLite3) ==
              Ecto.Adapters.Postgres

  if @postgres do
    @doc "Reads a top-level JSON key as text. Pass the key through `json_key/1`."
    defmacro json_text(field, key) do
      quote do: fragment("jsonb_extract_path_text(?, ?)", unquote(field), unquote(key))
    end

    @doc "Truncates a timestamp to the hour, for use as a grouping key."
    defmacro hour_bucket(timestamp) do
      quote do: fragment("date_trunc('hour', ?)", unquote(timestamp))
    end

    @doc "Returns the Unix time of the start of a `seconds`-wide bucket as an integer."
    defmacro epoch_bucket(timestamp, seconds) do
      quote do
        fragment(
          "(floor(extract(epoch from ?) / ?::bigint) * ?::bigint)::bigint",
          unquote(timestamp),
          unquote(seconds),
          unquote(seconds)
        )
      end
    end

    @doc "Converts a label name into the argument `json_text/2` expects."
    def json_key(key), do: to_string(key)

    @doc "Takes a lock held until the current transaction ends."
    def advisory_xact_lock(lock_id) do
      ZentinelCp.Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_id])
      :ok
    end
  else
    defmacro json_text(field, key) do
      quote do: fragment("json_extract(?, ?)", unquote(field), unquote(key))
    end

    defmacro hour_bucket(timestamp) do
      quote do: fragment("strftime('%Y-%m-%d %H', ?)", unquote(timestamp))
    end

    defmacro epoch_bucket(timestamp, seconds) do
      quote do
        fragment(
          "(CAST(strftime('%s', ?) AS INTEGER) / ? * ?)",
          unquote(timestamp),
          unquote(seconds),
          unquote(seconds)
        )
      end
    end

    def json_key(key) do
      escaped = key |> to_string() |> String.replace(~S("), ~S(\"))
      ~s($."#{escaped}")
    end

    # SQLite allows one writer at a time, so no lock is needed.
    def advisory_xact_lock(_lock_id), do: :ok
  end
end
