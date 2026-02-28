defmodule Revix.Mailer do
  use Swoosh.Mailer, otp_app: :revix

  def sender do
    config = Application.get_env(:revix, :sender, [])
    {config[:name] || "Revix", config[:email] || "revix@example.com"}
  end
end
