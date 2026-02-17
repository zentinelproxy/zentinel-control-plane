defmodule ZentinelCp.Observability.Tracer do
  @moduledoc """
  OpenTelemetry tracing for key control plane operations.

  Wraps `OpenTelemetry.Tracer.with_span/3` to create spans for bundle
  compilation, rollout lifecycle, webhook processing, and node heartbeats.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Executes a function within a traced OpenTelemetry span.

  Attributes from the metadata map are set on the span.
  """
  def span(span_name, metadata, fun) when is_atom(span_name) and is_map(metadata) do
    attributes = Enum.map(metadata, fn {k, v} -> {to_string(k), to_string(v)} end)

    Tracer.with_span :"zentinel_cp.#{span_name}", %{attributes: attributes} do
      try do
        fun.()
      rescue
        e ->
          Tracer.set_status(:error, Exception.message(e))
          reraise e, __STACKTRACE__
      end
    end
  end

  @doc """
  Wraps a bundle compilation pipeline with tracing spans.
  """
  def trace_compilation(bundle_id, fun) do
    span(:bundle_compilation, %{bundle_id: bundle_id}, fun)
  end

  @doc """
  Wraps a rollout tick with tracing spans.
  """
  def trace_rollout_tick(rollout_id, fun) do
    span(:rollout_tick, %{rollout_id: rollout_id}, fun)
  end

  @doc """
  Wraps webhook processing with tracing spans.
  """
  def trace_webhook(provider, fun) do
    span(:webhook_processing, %{provider: provider}, fun)
  end

  @doc """
  Wraps node heartbeat processing with tracing spans.
  """
  def trace_heartbeat(node_id, fun) do
    span(:node_heartbeat, %{node_id: node_id}, fun)
  end
end
