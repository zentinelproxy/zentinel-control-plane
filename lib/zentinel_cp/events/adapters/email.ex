defmodule ZentinelCp.Events.Adapters.Email do
  @moduledoc """
  Email notification adapter using Swoosh.
  """

  import Swoosh.Email

  def format_payload(event) do
    subject = "[Zentinel CP] #{event.type}"

    body = """
    Event: #{event.type}
    Time: #{DateTime.to_iso8601(event.emitted_at)}

    Details:
    #{format_details(event.payload)}
    """

    %{subject: subject, body: body}
  end

  def deliver(to, from, subject, body) do
    email =
      new()
      |> to(to)
      |> from(from)
      |> subject(subject)
      |> text_body(body)

    ZentinelCp.Mailer.deliver(email)
  end

  defp format_details(payload) when map_size(payload) == 0, do: "No additional details"

  defp format_details(payload) do
    payload
    |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
    |> Enum.join("\n")
  end
end
