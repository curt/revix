defmodule Revix.MailerProbe do
  @moduledoc """
  Verifies the SMTP relay at startup by opening (and immediately closing) a
  session with `gen_smtp` — the same library path `Swoosh.Adapters.SMTP` uses
  to deliver mail. The connect → EHLO → STARTTLS → AUTH handshake is exercised
  without sending any mail.

  Called from `config/runtime.exs` when SMTP is enabled, so a misconfigured
  relay aborts the boot instead of failing on the first outbound email.
  """

  alias Revix.MailerConfig

  @doc """
  Returns `:ok` when a session can be opened, or an `{:error, reason}` tuple
  from `gen_smtp` otherwise.

  `opts` is the SMTP keyword config built by `Revix.MailerConfig`; when not
  given it is read from the current environment configuration.
  """
  def check(opts \\ nil) do
    opts = opts || MailerConfig.smtp_config() || []

    case Keyword.get(opts, :relay) do
      nil -> {:error, :relay_not_configured}
      _relay -> open(opts)
    end
  end

  defp open(opts) do
    with {:ok, _apps} <- Application.ensure_all_started(:ssl),
         {:ok, session} <- :gen_smtp_client.open(Keyword.delete(opts, :adapter)) do
      _ = :gen_smtp_client.close(session)
      :ok
    end
  end
end
