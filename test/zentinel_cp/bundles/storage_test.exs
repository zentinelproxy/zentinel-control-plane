defmodule ZentinelCp.Bundles.StorageTest do
  use ExUnit.Case, async: false

  alias ZentinelCp.Bundles.Storage

  setup do
    original = Application.get_env(:zentinel_cp, Storage)
    on_exit(fn -> Application.put_env(:zentinel_cp, Storage, original) end)
  end

  test "presigns S3 URLs from the configured endpoint" do
    Application.put_env(:zentinel_cp, Storage,
      bucket: "bundles",
      ex_aws_config: [
        access_key_id: "key",
        secret_access_key: "secret",
        scheme: "http://",
        host: "storage.internal",
        port: 9000,
        region: "us-east-1"
      ]
    )

    assert {:ok, url} = Storage.presigned_url("bundles/abc.tar.zst", 60)
    assert url =~ "http://storage.internal:9000/bundles/bundles/abc.tar.zst?"
    assert url =~ "X-Amz-Signature="
    refute url =~ "secret"
  end
end
