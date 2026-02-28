defmodule RevixWeb.PersonSessionHTML do
  use RevixWeb, :html

  embed_templates "person_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:revix, Revix.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
