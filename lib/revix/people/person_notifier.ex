defmodule Revix.People.PersonNotifier do
  import Swoosh.Email

  alias Revix.Mailer
  alias Revix.People.Person

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Mailer.sender())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a person email.
  """
  def deliver_update_email_instructions(person, url) do
    deliver(person.email, "Update email instructions", """

    ==============================

    Hi #{person.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to sign in with a magic link.
  """
  def deliver_login_instructions(person, url) do
    case person do
      %Person{confirmed_at: nil} -> deliver_confirmation_instructions(person, url)
      _ -> deliver_magic_link_instructions(person, url)
    end
  end

  defp deliver_magic_link_instructions(person, url) do
    deliver(person.email, "Sign in instructions", """

    ==============================

    Hi #{person.email},

    You can sign into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(person, url) do
    deliver(person.email, "Confirmation instructions", """

    ==============================

    Hi #{person.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
