defmodule ZentinelCp.Auth.SamlValidator do
  @moduledoc """
  Validates SAML responses with esaml: XML signature against the provider's
  certificate, audience, recipient, expiry, issuer and `InResponseTo`.
  """

  require Record

  Record.defrecordp(
    :esaml_sp,
    Record.extract(:esaml_sp, from_lib: "esaml/include/esaml.hrl")
  )

  Record.defrecordp(
    :esaml_assertion,
    Record.extract(:esaml_assertion, from_lib: "esaml/include/esaml.hrl")
  )

  Record.defrecordp(
    :esaml_subject,
    Record.extract(:esaml_subject, from_lib: "esaml/include/esaml.hrl")
  )

  @max_response_bytes 512_000

  @doc """
  Validates a decoded SAML response.

  Required options: `:audience`, `:recipient`, `:request_id`.
  Returns `{:ok, %{name_id: name, attributes: map}}` or `{:error, reason}`.
  """
  def validate(xml, provider, opts) when is_binary(xml) do
    with :ok <- check_shape(xml),
         {:ok, fingerprint} <- certificate_fingerprint(provider.certificate),
         {:ok, document} <- parse(xml),
         {:ok, assertion} <- validate_assertion(document, fingerprint, opts),
         :ok <- check_issuer(assertion, provider),
         :ok <- check_in_response_to(assertion, opts[:request_id]) do
      subject = esaml_assertion(assertion, :subject)

      {:ok,
       %{
         name_id: to_string(esaml_subject(subject, :name)),
         attributes: attributes(esaml_assertion(assertion, :attributes))
       }}
    end
  end

  # A SAML response never needs a DTD, and esaml has an unpatched XXE advisory, so
  # DTDs are rejected before parsing. Other encodings are rejected too, because a
  # DTD in UTF-16 would not be found by this check.
  defp check_shape(xml) when byte_size(xml) > @max_response_bytes,
    do: {:error, :response_too_large}

  defp check_shape(xml) do
    cond do
      not String.valid?(xml) or String.contains?(xml, <<0>>) -> {:error, :invalid_encoding}
      Regex.match?(~r/^\s*<\?xml[^>]*encoding=["'](?!utf-8)/i, xml) -> {:error, :invalid_encoding}
      String.contains?(xml, "<!") -> {:error, :dtd_not_allowed}
      true -> :ok
    end
  end

  defp certificate_fingerprint(certificate) do
    case certificate_der(certificate) do
      {:ok, der} -> {:ok, {:sha256, :crypto.hash(:sha256, der)}}
      :error -> {:error, :invalid_certificate}
    end
  end

  defp certificate_der(certificate) do
    case :public_key.pem_decode(certificate) do
      [{:Certificate, der, :not_encrypted} | _] -> {:ok, der}
      _ -> certificate |> String.replace(~r/\s+/, "") |> Base.decode64()
    end
  end

  defp parse(xml) do
    {document, _rest} =
      xml
      |> String.to_charlist()
      |> :xmerl_scan.string(namespace_conformant: true, quiet: true, allow_entities: false)

    {:ok, document}
  catch
    :exit, _ -> {:error, :malformed_xml}
  end

  defp validate_assertion(document, fingerprint, opts) do
    audience = String.to_charlist(opts[:audience])

    sp =
      esaml_sp(
        idp_signs_assertions: true,
        idp_signs_envelopes: false,
        trusted_fingerprints: [fingerprint],
        metadata_uri: audience,
        entity_id: audience,
        consume_uri: String.to_charlist(opts[:recipient])
      )

    case :esaml_sp.validate_assertion(document, sp) do
      {:ok, assertion} -> {:ok, assertion}
      {:error, reason} -> {:error, reason}
    end
  catch
    kind, reason when kind in [:error, :exit, :throw] -> {:error, {:invalid_assertion, reason}}
  end

  defp check_issuer(assertion, provider) do
    if to_string(esaml_assertion(assertion, :issuer)) == provider.entity_id,
      do: :ok,
      else: {:error, :issuer_mismatch}
  end

  defp check_in_response_to(assertion, request_id) when is_binary(request_id) do
    subject = esaml_assertion(assertion, :subject)

    if to_string(esaml_subject(subject, :in_response_to)) == request_id,
      do: :ok,
      else: {:error, :in_response_to_mismatch}
  end

  defp check_in_response_to(_assertion, _request_id), do: {:error, :missing_request_id}

  defp attributes(attributes) do
    Map.new(attributes, fn {name, value} -> {to_string(name), attribute_value(value)} end)
  end

  # esaml returns a charlist for one value and a list of charlists for several.
  defp attribute_value([first | _] = values) when is_list(first) do
    Enum.map(values, &to_string/1)
  end

  defp attribute_value(value), do: [to_string(value)]
end
