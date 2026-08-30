defmodule RevixWeb.PersonRegistrationController do
  use RevixWeb, :controller

  alias Revix.People
  alias Revix.People.Person

  def new(conn, _params) do
    changeset = People.change_person_email(%Person{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"person" => person_params}) do
    case People.register_person(person_params, &person_uri/1, &person_url/2) do
      {:ok, person} ->
        {:ok, _} =
          People.deliver_login_instructions(
            person,
            &url(~p"/people/signin/#{&1}"),
            endpoint: RevixWeb.CanonicalRoutes.home_url()
          )

        conn
        |> put_flash(
          :info,
          "An email was sent to #{person.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/people/signin")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
