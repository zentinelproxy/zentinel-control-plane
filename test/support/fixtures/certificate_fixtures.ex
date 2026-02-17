defmodule ZentinelCp.CertificateFixtures do
  @moduledoc """
  Test helpers for creating Certificate entities.
  """

  # Self-signed test certificate for test.example.com
  # Generated via: openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=test.example.com/O=Test Org"
  @test_cert_pem "-----BEGIN CERTIFICATE-----\nMIIDPTCCAiWgAwIBAgIUPh/55Cx+D8eC4Vng1tl8DA509EUwDQYJKoZIhvcNAQEL\nBQAwLjEZMBcGA1UEAwwQdGVzdC5leGFtcGxlLmNvbTERMA8GA1UECgwIVGVzdCBP\ncmcwHhcNMjYwMjEyMTU1MDIzWhcNMjcwMjEyMTU1MDIzWjAuMRkwFwYDVQQDDBB0\nZXN0LmV4YW1wbGUuY29tMREwDwYDVQQKDAhUZXN0IE9yZzCCASIwDQYJKoZIhvcN\nAQEBBQADggEPADCCAQoCggEBAMgnaWfQmFvQyRi8wKUrUpsyvyFCanSzi/cIb2Kq\nB3jwgSjhPIgU6t36kQ5vkHJ99HmQLxi0jqxvxEzdn5id2SLqYpYkyCYU2Lo3tC+R\nSP+SYpp4t0qar2tt6FEBqIOG2clq2HRxwFKnVNfCzUCeJlHkGeO9ItfsCkTqALrb\n1rFesF+YG97M4mPC3DrEPzCJFWXbZpM682Q2fV/xwKEkdPwY4yk3H/lVVdT5rG2W\nr1SOWTzJGBbcWzvCgRzu6DjZbIm3aqIhi91RZulMi1wcPPmwzlj5OjSR9OqRktiP\nAQvFq8mF5ovTIJQNVFIwjlm0mUSDEM8qsocobjXoLfmdhOUCAwEAAaNTMFEwHQYD\nVR0OBBYEFOuCjIzV0EV/3RxQnGXlUObF6D81MB8GA1UdIwQYMBaAFOuCjIzV0EV/\n3RxQnGXlUObF6D81MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB\nAKHK5slVGavOQEUxN4/+HuvZVQ3ekugD1k71BSpjRA64S9/UWFkvLIrzcDJ1C8Ou\nWwKpghc8m3wMaKUbZk2uYTShq7EK4y/rPUGRk2EtKaYUICPL9ECiVuRg5Om0HZzL\nob18wDdjPYbcBtb2/lGXtz91nRnTRAPhomHGAOmr9D9UxJcHEr588S1DYlH+Ne1+\nL8teQZ9WqJqvRRR1Y8wjns+PzwBS/rQHmwdUzF04olsNAjOS10+JYX+z643/eCiO\nGcPWPrRDX8J6vRLN4EFmh7fgakoiC1kms8sf02DtOy0xPn9W/O6zsdWlZW65gwCh\ni7J6n+Ctl2r5qgaL9KprCXg=\n-----END CERTIFICATE-----"

  @test_key_pem "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDIJ2ln0Jhb0MkY\nvMClK1KbMr8hQmp0s4v3CG9iqgd48IEo4TyIFOrd+pEOb5ByffR5kC8YtI6sb8RM\n3Z+Yndki6mKWJMgmFNi6N7QvkUj/kmKaeLdKmq9rbehRAaiDhtnJath0ccBSp1TX\nws1AniZR5BnjvSLX7ApE6gC629axXrBfmBvezOJjwtw6xD8wiRVl22aTOvNkNn1f\n8cChJHT8GOMpNx/5VVXU+axtlq9Ujlk8yRgW3Fs7woEc7ug42WyJt2qiIYvdUWbp\nTItcHDz5sM5Y+To0kfTqkZLYjwELxavJheaL0yCUDVRSMI5ZtJlEgxDPKrKHKG41\n6C35nYTlAgMBAAECggEACsdOjpPl5InjjnS5thtVZTywHMEoHPU/TBQU9X39DYb8\nGaC5gwWHWWFhNuMMpxG/3N0GIEE27rPNISuNKOmVNCNloDrGWYClZC/UQPyErxip\nvTJTgo2+dR1T1arucXjNWSKrGeg3SGww7jaUGY76ts2/FCvPCMwyCGCGnglxMBd2\nK9w5o1UtEDcKNuCgx+y1AJAC6kvssYYHu0bRBeMylPd19fnGw2ihkJl2K6mmnhZQ\nU5rJaSboCnCdQeXpdOPZzZGzErmJHRxOmRNZaJY/+XDlx+QY0V4WfYoZG+ugjUC4\nC5VyvyjFeD15e3KJldMmhbhgnexZBS8XrJM1EsO48QKBgQDk6pZs3p6C35YJlX80\nOqlWC7XxApBp3hXuEht3ToUCEYD9B/qx7msZFUEoU6xfcAidd03hxBqoBBNYgY5e\ngmWWGITcPuoLvI21PS9sdAEP8wYk7sJu9uGxvLiJfhWXZYochPPQoVsFWtN6PNot\nCYpaiOmKUqbKjGt1XYRCoRhhNQKBgQDf1atPicvyyrD9YCv88FyyebeIE2zTziPO\nMHAmtT0SwdMcvIUTfD438dwcp6o0o0x9fImXawPpfHAOOIibWn1vTQUHdO0Np4+5\neoCkZZnpPqyaq0UovkjjzWLBNuC+QQGZb/Ky11YYbhdTkd0Be+x9vYLVSzYGJwN8\n7CD+VZQ68QKBgGzeJCwis8AKFZD5SEXOoDoL17uHPKcct9FBS06ySQ9yw6WS5ec5\nPDXxpctH//JjlbVNx/xXB1ZgmdK9yrenzChWANm+EhEC22IWdzdc9CRhr8pgwpeD\nUlL1Lc416I7X+5cUo9/U3TTuvSSlTB2fK+1ir67ZH/m0TmbC0uPdOXsBAoGASZrq\n1aH7liB/KSLp9ChaYzpRVwcEP3ZHIfOdvazVo4hnUsjPfgPaNe1rs2STPPICIjXE\nzS0cwTfxZUvD6EpOez45jCUwGtBiG90j1muuvBunCMmPWYGRWI/ejKjuKMIZs4oz\npgnXvvrc4tdRdL56mzKphlhQMJ+9ruO7Scd8khECgYEAte5FXAxLycJ0/UeA9aDp\nFhupQLbNrlQhJVwGfgNvMfx7IySJTSVgJgVTD2xRdHxN/i7hUEdyB8X+MWkkLJ/G\nLQ7MPkj0pP5gEjIWmh92XjBwR/Ts4xpn5jGzvIPHdUPDFaEZBvbZi3nXoXpkbnnz\nQC67wQXVLGui6tUCWNJ7TeA=\n-----END PRIVATE KEY-----"

  def test_cert_pem, do: @test_cert_pem
  def test_key_pem, do: @test_key_pem

  def unique_cert_name, do: "cert-#{System.unique_integer([:positive])}"

  def certificate_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, cert} =
      ZentinelCp.Services.create_certificate(%{
        name: attrs[:name] || unique_cert_name(),
        domain: attrs[:domain] || "test.example.com",
        cert_pem: attrs[:cert_pem] || test_cert_pem(),
        key_pem: attrs[:key_pem] || test_key_pem(),
        ca_chain_pem: attrs[:ca_chain_pem],
        auto_renew: attrs[:auto_renew] || false,
        project_id: project.id
      })

    cert
  end
end
