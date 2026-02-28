defmodule RevixWeb.PersonSessionController do
  use RevixWeb, :controller

  alias Revix.People
  alias RevixWeb.PersonAuth

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:person), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "person")

    render(conn, :new, form: form)
  end

  # magic link login
  def create(conn, %{"person" => %{"token" => token} = person_params} = params) do
    info =
      case params do
        %{"_action" => "confirmed"} -> "Person confirmed successfully."
        _ -> "Welcome back!"
      end

    case People.login_person_by_magic_link(token) do
      {:ok, {person, _expired_tokens}} ->
        conn
        |> put_flash(:info, info)
        |> PersonAuth.log_in_person(person, person_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> render(:new, form: Phoenix.Component.to_form(%{}, as: "person"))
    end
  end

  # email + password login
  def create(conn, %{"person" => %{"email" => email, "password" => password} = person_params}) do
    if person = People.get_person_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> PersonAuth.log_in_person(person, person_params)
    else
      form = Phoenix.Component.to_form(person_params, as: "person")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> render(:new, form: form)
    end
  end

  # magic link request
  def create(conn, %{"person" => %{"email" => email}}) do
    if person = People.get_person_by_email(email) do
      People.deliver_login_instructions(
        person,
        &url(~p"/people/signin/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/people/signin")
  end

  def confirm(conn, %{"token" => token}) do
    if person = People.get_person_by_magic_link_token(token) do
      form = Phoenix.Component.to_form(%{"token" => token}, as: "person")

      conn
      |> assign(:person, person)
      |> assign(:form, form)
      |> render(:confirm)
    else
      conn
      |> put_flash(:error, "Magic link is invalid or it has expired.")
      |> redirect(to: ~p"/people/signin")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> PersonAuth.log_out_person()
  end
end
