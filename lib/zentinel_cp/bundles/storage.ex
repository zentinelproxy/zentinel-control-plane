defmodule ZentinelCp.Bundles.Storage do
  @moduledoc """
  Storage adapter for bundle artifacts using S3/MinIO via ExAws.
  """

  @doc """
  Uploads data to the configured bucket.
  """
  def upload(key, data) when is_binary(data) do
    if local_storage?() do
      local_upload(key, data)
    else
      bucket()
      |> ExAws.S3.put_object(key, data, content_type: "application/gzip")
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:upload_failed, reason}}
      end
    end
  end

  @doc """
  Downloads data from the configured bucket.
  """
  def download(key) do
    if local_storage?() do
      local_download(key)
    else
      bucket()
      |> ExAws.S3.get_object(key)
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, %{body: body}} -> {:ok, body}
        {:error, reason} -> {:error, {:download_failed, reason}}
      end
    end
  end

  @doc """
  Generates a presigned URL for downloading a bundle.
  """
  def presigned_url(key, expires_in \\ 3600) do
    if local_storage?() do
      {:ok, "/local-storage/#{key}"}
    else
      config = ex_aws_config()
      ExAws.S3.presigned_url(config, :get, bucket(), key, expires_in: expires_in)
    end
  end

  @doc """
  Deletes an object from the configured bucket.
  """
  def delete(key) do
    if local_storage?() do
      local_delete(key)
    else
      bucket()
      |> ExAws.S3.delete_object(key)
      |> ExAws.request(ex_aws_config())
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:delete_failed, reason}}
      end
    end
  end

  @doc """
  Generates a storage key for a bundle.
  """
  def storage_key(project_id, bundle_id) do
    "bundles/#{project_id}/#{bundle_id}.tar.zst"
  end

  defp bucket do
    storage_config()
    |> Keyword.get(:bucket, "zentinel-bundles")
  end

  defp ex_aws_config do
    storage_config()
    |> Keyword.get(:ex_aws_config, [])
  end

  defp local_storage? do
    storage_config()
    |> Keyword.get(:backend, :s3) == :local
  end

  defp local_storage_dir do
    storage_config()
    |> Keyword.get(:local_dir, Path.expand("priv/bundles"))
  end

  defp storage_config do
    Application.get_env(:zentinel_cp, __MODULE__, [])
  end

  defp local_upload(key, data) do
    path = Path.join(local_storage_dir(), key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, data)
    :ok
  end

  defp local_download(key) do
    path = Path.join(local_storage_dir(), key)

    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:download_failed, reason}}
    end
  end

  defp local_delete(key) do
    path = Path.join(local_storage_dir(), key)
    File.rm(path)
    :ok
  end
end
