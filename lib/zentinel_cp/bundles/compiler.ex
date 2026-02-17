defmodule ZentinelCp.Bundles.Compiler do
  @moduledoc """
  Compiler service for Zentinel configuration bundles.

  Validates KDL config via `zentinel validate`, assembles tar.zst archives,
  and computes checksums.
  """

  require Logger

  @doc """
  Validates a KDL configuration string.
  Returns {:ok, output} or {:error, output}.
  """
  def validate(config_source) when is_binary(config_source) do
    if skip_validation?() do
      Logger.info("Skipping zentinel validation (dev mode)")
      {:ok, "Validation skipped (dev mode)"}
    else
      with {:ok, tmpfile} <- write_temp_config(config_source) do
        try do
          case System.cmd(zentinel_binary(), ["validate", "--config", tmpfile],
                 stderr_to_stdout: true
               ) do
            {output, 0} -> {:ok, output}
            {output, _code} -> {:error, output}
          end
        rescue
          e in ErlangError ->
            {:error, "Failed to run zentinel binary: #{inspect(e)}"}
        after
          File.rm(tmpfile)
        end
      end
    end
  end

  @doc """
  Assembles a bundle archive from config source.
  Returns {:ok, %{archive: binary, checksum: string, size: integer, manifest: map}}
  or {:error, reason}.
  """
  def assemble(bundle_id, config_source, extra_files \\ []) when is_binary(config_source) do
    tmpdir = Path.join(System.tmp_dir!(), "zentinel-bundle-#{bundle_id}")
    File.mkdir_p!(tmpdir)

    try do
      # Write config
      config_path = Path.join(tmpdir, "zentinel.kdl")
      File.write!(config_path, config_source)

      # Write extra files
      extra_file_entries =
        Enum.map(extra_files, fn {relative_path, content} ->
          full_path = Path.join(tmpdir, relative_path)
          File.mkdir_p!(Path.dirname(full_path))
          File.write!(full_path, content || "")

          %{
            "path" => relative_path,
            "checksum" => checksum(content || ""),
            "size" => byte_size(content || "")
          }
        end)

      # Create manifest
      config_checksum = checksum(config_source)

      manifest = %{
        "bundle_id" => bundle_id,
        "assembled_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "files" =>
          [
            %{
              "path" => "zentinel.kdl",
              "checksum" => config_checksum,
              "size" => byte_size(config_source)
            }
          ] ++ extra_file_entries
      }

      manifest_json = Jason.encode!(manifest, pretty: true)
      manifest_path = Path.join(tmpdir, "manifest.json")
      File.write!(manifest_path, manifest_json)

      # Build file list for archive
      extra_paths = Enum.map(extra_files, fn {path, _} -> path end)
      all_files = ["zentinel.kdl"] ++ extra_paths ++ ["manifest.json"]

      # Create tar.zst archive
      archive = create_archive(tmpdir, all_files)
      archive_checksum = checksum(archive)

      {:ok,
       %{
         archive: archive,
         checksum: archive_checksum,
         size: byte_size(archive),
         manifest: manifest
       }}
    rescue
      e ->
        {:error, "Assembly failed: #{Exception.message(e)}"}
    after
      File.rm_rf(tmpdir)
    end
  end

  @doc """
  Computes SHA256 checksum of data.
  """
  def checksum(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp write_temp_config(config_source) do
    tmpfile =
      Path.join(System.tmp_dir!(), "zentinel-validate-#{System.unique_integer([:positive])}.kdl")

    case File.write(tmpfile, config_source) do
      :ok -> {:ok, tmpfile}
      {:error, reason} -> {:error, "Failed to write temp config: #{inspect(reason)}"}
    end
  end

  defp create_archive(dir, files) do
    # Create a tar archive, then compress with zstd if available, otherwise gzip
    tar_data = create_tar(dir, files)

    case System.cmd("which", ["zstd"], stderr_to_stdout: true) do
      {_, 0} -> compress_zstd(tar_data)
      _ -> compress_gzip(tar_data)
    end
  end

  defp create_tar(dir, files) do
    # Use Erlang's :erl_tar — write to temp file then read back
    # (OTP 28 removed in-memory binary support from create/2)
    tmptar = Path.join(System.tmp_dir!(), "bundle-tar-#{System.unique_integer([:positive])}.tar")

    file_entries =
      Enum.map(files, fn file ->
        path = Path.join(dir, file)
        content = File.read!(path)
        {String.to_charlist(file), content}
      end)

    :ok = :erl_tar.create(String.to_charlist(tmptar), file_entries)
    tar_data = File.read!(tmptar)
    File.rm!(tmptar)
    tar_data
  end

  defp compress_zstd(data) do
    tmpfile = Path.join(System.tmp_dir!(), "bundle-#{System.unique_integer([:positive])}.tar")
    outfile = tmpfile <> ".zst"

    try do
      File.write!(tmpfile, data)
      {_, 0} = System.cmd("zstd", ["-q", "--rm", tmpfile, "-o", outfile])
      File.read!(outfile)
    after
      File.rm(tmpfile)
      File.rm(outfile)
    end
  end

  defp compress_gzip(data) do
    :zlib.gzip(data)
  end

  defp zentinel_binary do
    compiler_config()
    |> Keyword.get(:zentinel_binary, "zentinel")
  end

  defp skip_validation? do
    compiler_config()
    |> Keyword.get(:skip_validation, false)
  end

  defp compiler_config do
    Application.get_env(:zentinel_cp, __MODULE__, [])
  end
end
