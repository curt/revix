defmodule RevixWeb.PersonRegistrationController do
  use RevixWeb, :controller

  alias Revix.People
  alias Revix.People.Person
  alias RevixWeb.SignInThrottle

  def new(conn, _params) do
    changeset = People.change_person_email(%Person{})
    render(conn, :new, changeset: changeset)
  end

  # A registered email gets the same response as a new one, and its owner gets
  # a sign-in link, so the form doesn't reveal which emails have accounts.
  # Both cases send email, so they share the magic-link rate limit.
  def create(conn, %{"person" => person_params}) do
    email = to_string(person_params["email"])

    conn
    |> SignInThrottle.check(:magic_link, email)
    |> sign_up(conn, person_params, email)
  end

  defp sign_up(:ok, conn, person_params, email) do
    person_params
    |> People.sign_up(&person_uri/1, &person_url/2)
    |> respond(conn, person_params, email)
  end

  # A bare changeset keeps the typed email in the form without validating it,
  # which would generate account keys and could show "already been taken".
  defp sign_up({:error, :rate_limited}, conn, _person_params, email) do
    conn
    |> put_status(:too_many_requests)
    |> put_flash(:error, "Too many attempts. Please wait a few minutes and try again.")
    |> render(:new, changeset: Ecto.Changeset.change(%Person{}, email: email))
  end

  defp respond({:error, %Ecto.Changeset{} = changeset}, conn, _person_params, _email) do
    render(conn, :new, changeset: changeset)
  end

  defp respond({_new_or_existing, person}, conn, _person_params, email) do
    {:ok, _} =
      People.deliver_login_instructions(
        person,
        &url(~p"/people/signin/#{&1}"),
        endpoint: RevixWeb.CanonicalRoutes.home_url()
      )

    conn
    |> put_flash(
      :info,
      "An email was sent to #{email}. Use the link in it to confirm your account or sign in."
    )
    |> redirect(to: ~p"/people/signin")
  end
end
