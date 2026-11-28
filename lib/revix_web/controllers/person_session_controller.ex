defmodule RevixWeb.PersonSessionController do
  use RevixWeb, :controller

  alias Revix.People
  alias RevixWeb.PersonAuth
  alias RevixWeb.SignInThrottle

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
      {:ok, {person, expired_tokens}} ->
        PersonAuth.disconnect_sessions(expired_tokens)

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
    conn
    |> SignInThrottle.check(:password, email)
    |> password_sign_in(conn, email, password, person_params)
  end

  # magic link request
  def create(conn, %{"person" => %{"email" => email} = person_params}) do
    conn
    |> SignInThrottle.check(:magic_link, email)
    |> request_magic_link(conn, email, person_params)
  end

  defp password_sign_in({:error, :rate_limited}, conn, _email, _password, person_params),
    do: rate_limited(conn, person_params)

  defp password_sign_in(:ok, conn, email, password, person_params) do
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

  defp request_magic_link({:error, :rate_limited}, conn, _email, person_params),
    do: rate_limited(conn, person_params)

  defp request_magic_link(:ok, conn, email, _person_params) do
    if person = People.get_person_by_email(email) do
      People.deliver_login_instructions(
        person,
        &url(~p"/people/signin/#{&1}"),
        endpoint: RevixWeb.CanonicalRoutes.home_url()
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/people/signin")
  end

  defp rate_limited(conn, person_params) do
    form = Phoenix.Component.to_form(Map.take(person_params, ["email"]), as: "person")

    conn
    |> put_status(:too_many_requests)
    |> put_flash(:error, "Too many sign-in attempts. Please wait a few minutes and try again.")
    |> render(:new, form: form)
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
