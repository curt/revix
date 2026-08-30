defmodule Revix.People.PersonNotifier do
  import Swoosh.Email

  alias Revix.Mailer
  alias Revix.People.Person
  alias Revix.Sites

  # Delivers the email using the application mailer. `subject` is the base line;
  # it is branded with the site name (when `:endpoint` is given) and suffixed
  # with a send timestamp so each request threads as its own conversation.
  defp deliver(recipient, subject, text, html, opts) do
    email =
      new()
      |> to(recipient)
      |> from(Mailer.sender())
      |> subject(subject_line(subject, opts))
      |> text_body(text)
      |> html_body(html)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp subject_line(base, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    stamp = Calendar.strftime(now, "%b %-d, %Y %H:%M UTC")

    [site_title(opts[:endpoint]), base, stamp]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" — ")
  end

  defp site_title(nil), do: nil

  defp site_title(endpoint) do
    case Sites.get_site_or_default(endpoint) do
      %{title: title} when is_binary(title) and title != "" -> title
      _ -> nil
    end
  end

  @doc """
  Deliver instructions to update a person email.

  `opts` accepts `:endpoint` (for site-name branding of the subject) and `:now`.
  """
  def deliver_update_email_instructions(person, url, opts \\ []) do
    deliver(
      person.email,
      "Update email instructions",
      """

      ==============================

      Hi #{person.email},

      You can change your email by visiting the URL below:

      #{url}

      If you didn't request this change, please ignore this.

      ==============================
      """,
      instructions_html(
        person,
        "You can change your email by visiting the link below:",
        url,
        "If you didn't request this change, please ignore this."
      ),
      opts
    )
  end

  @doc """
  Deliver instructions to sign in with a magic link.

  `opts` accepts `:endpoint` (for site-name branding of the subject) and `:now`.
  """
  def deliver_login_instructions(person, url, opts \\ []) do
    case person do
      %Person{confirmed_at: nil} -> deliver_confirmation_instructions(person, url, opts)
      _ -> deliver_magic_link_instructions(person, url, opts)
    end
  end

  defp deliver_magic_link_instructions(person, url, opts) do
    deliver(
      person.email,
      "Sign in instructions",
      """

      ==============================

      Hi #{person.email},

      You can sign into your account by visiting the URL below:

      #{url}

      If you didn't request this email, please ignore this.

      ==============================
      """,
      instructions_html(
        person,
        "You can sign into your account by visiting the link below:",
        url,
        "If you didn't request this email, please ignore this."
      ),
      opts
    )
  end

  defp deliver_confirmation_instructions(person, url, opts) do
    deliver(
      person.email,
      "Confirmation instructions",
      """

      ==============================

      Hi #{person.email},

      You can confirm your account by visiting the URL below:

      #{url}

      If you didn't create an account with us, please ignore this.

      ==============================
      """,
      instructions_html(
        person,
        "You can confirm your account by visiting the link below:",
        url,
        "If you didn't create an account with us, please ignore this."
      ),
      opts
    )
  end

  # `lead` and `disclaimer` are module-literal strings; only `person.email` and
  # `url` are dynamic and need escaping (mirrors DigestNotifier).
  defp instructions_html(person, lead, url, disclaimer) do
    """
    <p>Hi #{html_escape(person.email)},</p>
    <p>#{lead}</p>
    <p><a href="#{html_escape(url)}">#{html_escape(url)}</a></p>
    <p>#{disclaimer}</p>
    """
  end

  defp html_escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
