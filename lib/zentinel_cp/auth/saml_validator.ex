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

  # xmerl turns every element name, attribute name, namespace prefix and
  # namespace URI into an atom, and atoms are never freed, so arbitrary names
  # in unauthenticated input could exhaust the atom table (esaml advisories
  # EEF-CVE-2026-105270 and EEF-CVE-2026-86696). Responses may only use names
  # that already exist as atoms; this vocabulary makes sure SAML's do.
  @known_names ~w(
    Response Assertion Issuer Status StatusCode StatusMessage StatusDetail Subject NameID
    SubjectConfirmation SubjectConfirmationData Conditions AudienceRestriction Audience
    OneTimeUse ProxyRestriction AuthnStatement AuthnContext AuthnContextClassRef
    AuthnContextDeclRef AuthenticatingAuthority SubjectLocality AttributeStatement Attribute
    AttributeValue EncryptedAssertion EncryptedAttribute EncryptedID Advice Extensions
    Signature SignedInfo CanonicalizationMethod SignatureMethod Reference Transforms Transform
    DigestMethod DigestValue SignatureValue KeyInfo X509Data X509Certificate X509IssuerSerial
    X509IssuerName X509SerialNumber X509SubjectName KeyName KeyValue RSAKeyValue Modulus Exponent
    InclusiveNamespaces
    ID Version IssueInstant Destination InResponseTo Consent Format NameQualifier
    SPNameQualifier SPProvidedID Method NotBefore NotOnOrAfter Recipient Address DNSName Name
    NameFormat FriendlyName Algorithm URI PrefixList Value AuthnInstant SessionIndex
    SessionNotOnOrAfter Id type nil lang
    xmlns xml xsi xs xsd saml saml2 samlp saml2p ds dsig ec md ns1 ns2 ns3 ns4 ns5 a b
    urn:oasis:names:tc:SAML:2.0:assertion urn:oasis:names:tc:SAML:2.0:protocol
    urn:oasis:names:tc:SAML:2.0:metadata http://www.w3.org/2000/09/xmldsig#
    http://www.w3.org/2001/10/xml-exc-c14n# http://www.w3.org/2001/XMLSchema
    http://www.w3.org/2001/XMLSchema-instance http://www.w3.org/2001/04/xmlenc#
    http://www.w3.org/XML/1998/namespace
  )a

  @doc false
  def known_names, do: @known_names

  @doc """
  Validates a decoded SAML response.

  Required options: `:audience`, `:recipient`, `:request_id`.
  Returns `{:ok, %{name_id: name, attributes: map}}` or `{:error, reason}`.
  """
  def validate(xml, provider, opts) when is_binary(xml) do
    with :ok <- check_shape(xml),
         :ok <- check_names(xml),
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

  # Rejects names outside the existing atoms, so parsing cannot grow the atom
  # table without bound. Fails closed: text the scan cannot read as a name is
  # looked up as one and rejected.
  defp check_names(xml) do
    tags = Regex.scan(~r/<\/?([^\s\/>]+)([^>]*)>/, xml)

    names =
      Enum.flat_map(tags, fn [_tag, name, attributes] ->
        attribute_names = Regex.scan(~r/([^\s=\/]+)\s*=\s*(["'])(.*?)\2/s, attributes)

        namespace_uris =
          for [_, attr, _, value] <- attribute_names,
              attr == "xmlns" or String.starts_with?(attr, "xmlns:"),
              do: value

        # A qualified name is checked by its parts: with both from the fixed
        # vocabulary, the qualified atoms xmerl makes form a bounded set.
        [name | Enum.map(attribute_names, fn [_, attr, _, _] -> attr end)]
        |> Enum.flat_map(&String.split(&1, ":", parts: 2))
        |> Kernel.++(namespace_uris)
      end)

    case Enum.find(Enum.uniq(names), &(not existing_atom?(&1))) do
      nil -> :ok
      name -> {:error, {:unexpected_xml_name, String.slice(name, 0, 64)}}
    end
  end

  defp existing_atom?(name) do
    _ = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
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
