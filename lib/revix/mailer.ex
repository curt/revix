defmodule Revix.Mailer do
  use Swoosh.Mailer, otp_app: :revix

  @doc """
  The `{name, email}` tuple for the `From:` header.

  `name_override` (e.g. the configured site title) takes precedence over the
  static `config :revix, :sender` name; a `nil` override falls back to it.
  """
  def sender(name_override \\ nil) do
    config = Application.get_env(:revix, :sender, [])
    {name_override || config[:name] || "Revix", config[:email] || "revix@example.com"}
  end
end
