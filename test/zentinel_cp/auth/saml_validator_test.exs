defmodule ZentinelCp.Auth.SamlValidatorTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Auth.SamlValidator

  @audience "https://cp.example.com"
  @recipient "https://cp.example.com/auth/saml/acs"
  @issuer "https://idp.example.com"
  @request_id "_request-1"

  setup_all do
    %{cert: cert, key: key} = :public_key.pkix_test_root_cert(~c"idp", key: {:rsa, 2048, 65_537})

    %{cert: other_cert, key: other_key} =
      :public_key.pkix_test_root_cert(~c"evil", key: {:rsa, 2048, 65_537})

    {:ok, cert: cert, key: key, other_cert: other_cert, other_key: other_key}
  end

  defp provider(cert) do
    %{
      entity_id: @issuer,
      certificate: :public_key.pem_encode([{:Certificate, cert, :not_encrypted}])
    }
  end

  defp options, do: [audience: @audience, recipient: @recipient, request_id: @request_id]

  defp timestamp(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp assertion_xml(overrides \\ []) do
    name = overrides[:name] || "alice@example.com"
    audience = overrides[:audience] || @audience
    issuer = overrides[:issuer] || @issuer
    in_response_to = overrides[:in_response_to] || @request_id
    not_after = overrides[:not_after] || timestamp(300)

    """
    <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_a1" Version="2.0" IssueInstant="#{timestamp(0)}"><saml:Issuer>#{issuer}</saml:Issuer><saml:Subject><saml:NameID>#{name}</saml:NameID><saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer"><saml:SubjectConfirmationData InResponseTo="#{in_response_to}" NotOnOrAfter="#{not_after}" Recipient="#{@recipient}"/></saml:SubjectConfirmation></saml:Subject><saml:Conditions NotOnOrAfter="#{not_after}"><saml:AudienceRestriction><saml:Audience>#{audience}</saml:Audience></saml:AudienceRestriction></saml:Conditions><saml:AttributeStatement><saml:Attribute Name="groups"><saml:AttributeValue>admins</saml:AttributeValue></saml:Attribute></saml:AttributeStatement></saml:Assertion>
    """
    |> String.trim()
  end

  defp sign(xml, key, cert) do
    {element, _} =
      xml |> String.to_charlist() |> :xmerl_scan.string(namespace_conformant: true, quiet: true)

    signed = :xmerl_dsig.sign(element, key, cert)

    [signed]
    |> :xmerl.export(:xmerl_xml, prolog: [])
    |> :unicode.characters_to_binary()
  end

  defp response(assertion) do
    """
    <samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_r1" Version="2.0" IssueInstant="#{timestamp(0)}" Destination="#{@recipient}"><saml:Issuer>#{@issuer}</saml:Issuer><samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>#{assertion}</samlp:Response>
    """
    |> String.trim()
  end

  test "accepts an assertion signed by the provider", %{cert: cert, key: key} do
    xml = assertion_xml() |> sign(key, cert) |> response()

    assert {:ok, %{name_id: "alice@example.com", attributes: attributes}} =
             SamlValidator.validate(xml, provider(cert), options())

    assert attributes["groups"] == ["admins"]
  end

  test "rejects an unsigned assertion", %{cert: cert} do
    xml = assertion_xml() |> response()
    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects an assertion signed by another key", %{
    cert: cert,
    other_cert: other_cert,
    other_key: other_key
  } do
    xml = assertion_xml() |> sign(other_key, other_cert) |> response()
    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects an edited assertion", %{cert: cert, key: key} do
    xml =
      assertion_xml()
      |> sign(key, cert)
      |> String.replace("alice@example.com", "admin@example.com")
      |> response()

    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects a signed assertion wrapped around a forged one", %{cert: cert, key: key} do
    signed = assertion_xml() |> sign(key, cert)
    forged = assertion_xml(name: "admin@example.com")

    assert {:error, _} =
             SamlValidator.validate(response(forged <> signed), provider(cert), options())
  end

  test "rejects the wrong audience", %{cert: cert, key: key} do
    xml = assertion_xml(audience: "https://other.example.com") |> sign(key, cert) |> response()
    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects an expired assertion", %{cert: cert, key: key} do
    xml = assertion_xml(not_after: timestamp(-600)) |> sign(key, cert) |> response()
    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects the wrong issuer", %{cert: cert, key: key} do
    xml = assertion_xml(issuer: "https://evil.example.com") |> sign(key, cert) |> response()
    assert {:error, _} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects a response to another request", %{cert: cert, key: key} do
    xml = assertion_xml(in_response_to: "_other") |> sign(key, cert) |> response()

    assert {:error, :in_response_to_mismatch} =
             SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects a response when no request is in progress", %{cert: cert, key: key} do
    xml = assertion_xml() |> sign(key, cert) |> response()

    assert {:error, :missing_request_id} =
             SamlValidator.validate(xml, provider(cert), Keyword.put(options(), :request_id, nil))
  end

  test "rejects a document type declaration", %{cert: cert} do
    xml = ~s(<!DOCTYPE foo [<!ENTITY x "y">]>) <> response(assertion_xml())
    assert {:error, :dtd_not_allowed} = SamlValidator.validate(xml, provider(cert), options())
  end

  test "rejects a document type declaration hidden in another encoding", %{cert: cert} do
    xml =
      :unicode.characters_to_binary(~s(<!DOCTYPE foo []><a/>), :utf8, {:utf16, :little})

    assert {:error, :invalid_encoding} = SamlValidator.validate(xml, provider(cert), options())

    declared = ~s(<?xml version="1.0" encoding="ISO-8859-1"?><a/>)

    assert {:error, :invalid_encoding} =
             SamlValidator.validate(declared, provider(cert), options())
  end

  test "rejects malformed XML", %{cert: cert} do
    assert {:error, _} = SamlValidator.validate("<not-closed", provider(cert), options())
  end
end
