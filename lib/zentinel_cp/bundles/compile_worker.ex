defmodule ZentinelCp.Bundles.CompileWorker do
  @moduledoc """
  Oban worker that compiles bundle configuration.

  Triggered when a new bundle is created. Validates the config,
  assembles the archive, uploads to storage, and updates the bundle record.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias ZentinelCp.{Audit, Plugins, Services}
  alias ZentinelCp.Bundles
  alias ZentinelCp.Bundles.{Compiler, Risk, Signing, Storage}
  alias ZentinelCp.Observability.Tracer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bundle_id" => bundle_id}}) do
    Tracer.trace_compilation(bundle_id, fn ->
      do_perform(bundle_id)
    end)
  end

  defp do_perform(bundle_id) do
    bundle = Bundles.get_bundle!(bundle_id)

    Logger.info("Starting compilation for bundle #{bundle_id}")

    # Mark as compiling
    {:ok, bundle} = Bundles.update_status(bundle, "compiling")

    case compile_bundle(bundle) do
      {:ok, result} ->
        # Sign the bundle if signing is enabled
        {signature, signing_key_id} = Signing.sign_bundle(result.archive_data)

        # Score risk against previous bundle
        {risk_level, risk_reasons} =
          Risk.score_against_previous(bundle.config_source, bundle.project_id)

        {:ok, _} =
          Bundles.update_compilation(bundle, %{
            status: "compiled",
            checksum: result.checksum,
            size_bytes: result.size,
            storage_key: result.storage_key,
            manifest: result.manifest,
            compiler_output: result.compiler_output,
            signature: signature,
            signing_key_id: signing_key_id,
            risk_level: risk_level,
            risk_reasons: risk_reasons
          })

        Audit.log_system_action("bundle.compiled", "bundle", bundle.id,
          project_id: bundle.project_id,
          metadata: %{
            checksum: result.checksum,
            size: result.size,
            signed: not is_nil(signature),
            risk_level: risk_level,
            risk_reasons: risk_reasons
          }
        )

        Phoenix.PubSub.broadcast(
          ZentinelCp.PubSub,
          "bundles:#{bundle.project_id}",
          {:bundle_compiled, bundle_id}
        )

        Logger.info("Bundle #{bundle_id} compiled (#{result.size} bytes)")
        :ok

      {:error, reason} ->
        compiler_output = if is_binary(reason), do: reason, else: inspect(reason)

        {:ok, _} =
          Bundles.update_compilation(bundle, %{
            status: "failed",
            compiler_output: compiler_output
          })

        Audit.log_system_action("bundle.compilation_failed", "bundle", bundle.id,
          project_id: bundle.project_id,
          metadata: %{error: compiler_output}
        )

        Phoenix.PubSub.broadcast(
          ZentinelCp.PubSub,
          "bundles:#{bundle.project_id}",
          {:bundle_failed, bundle_id}
        )

        Logger.error("Bundle #{bundle_id} compilation failed: #{compiler_output}")
        :ok
    end
  end

  defp compile_bundle(bundle) do
    extra_files = build_extra_files(bundle.project_id)

    with {:ok, compiler_output} <- Compiler.validate(bundle.config_source),
         {:ok, assembly} <- Compiler.assemble(bundle.id, bundle.config_source, extra_files),
         storage_key <- Storage.storage_key(bundle.project_id, bundle.id),
         :ok <- Storage.upload(storage_key, assembly.archive) do
      {:ok,
       %{
         checksum: assembly.checksum,
         size: assembly.size,
         storage_key: storage_key,
         manifest: assembly.manifest,
         compiler_output: compiler_output,
         archive_data: assembly.archive
       }}
    end
  end

  defp build_extra_files(project_id) do
    ca_files =
      case Services.get_internal_ca(project_id) do
        nil ->
          []

        ca ->
          [
            {"internal-ca/ca.pem", ca.ca_cert_pem},
            {"internal-ca/crl.pem", ca.crl_pem || ""}
          ]
      end

    plugin_files = Plugins.collect_plugin_files(project_id)

    ca_files ++ plugin_files
  end
end
