defmodule RevixWeb.PersonRegistrationControllerTest do
  use RevixWeb.ConnCase, async: true

  import Ecto.Query
  import Revix.PeopleFixtures

  alias Revix.People.Person
  alias Revix.People.PersonToken
  alias Revix.Repo

  describe "GET /people/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/people/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/people/signin"
      assert response =~ ~p"/people/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_person(person_fixture()) |> get(~p"/people/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /people/register" do
    @tag :capture_log
    test "creates account but does not sign in", %{conn: conn} do
      email = unique_person_email()

      conn =
        post(conn, ~p"/people/register", %{
          "person" => valid_person_attributes(email: email)
        })

      refute get_session(conn, :person_token)
      assert redirected_to(conn) == ~p"/people/signin"

      assert conn.assigns.flash["info"] ==
               "An email was sent to #{email}. Use the link in it to confirm your account or sign in."
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/people/register", %{
          "person" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end
  end

  describe "POST /people/register with an email that is already registered" do
    defp login_tokens(person) do
      Repo.aggregate(where(PersonToken, person_id: ^person.id, context: "login"), :count)
    end

    defp register(conn, email) do
      post(conn, ~p"/people/register", %{"person" => %{"email" => email}})
    end

    test "responds exactly as it does for a new email", %{conn: conn} do
      person = person_fixture()
      conn = register(conn, person.email)

      assert redirected_to(conn) == ~p"/people/signin"

      assert conn.assigns.flash["info"] ==
               "An email was sent to #{person.email}. Use the link in it to confirm your account or sign in."
    end

    test "emails the existing person a sign-in link instead", %{conn: conn} do
      person = person_fixture()
      before = login_tokens(person)

      register(conn, person.email)

      assert login_tokens(person) == before + 1
    end

    test "echoes the email as typed, not as stored", %{conn: conn} do
      person = person_fixture()
      typed = String.upcase(person.email)

      conn = register(conn, typed)

      assert conn.assigns.flash["info"] =~ "An email was sent to #{typed}."
      assert Repo.aggregate(where(Person, email: ^person.email), :count) == 1
    end
  end

  describe "POST /people/register rate limits" do
    test "stops sending email to one address after three requests", %{conn: conn} do
      person = person_fixture()
      before = Repo.aggregate(where(PersonToken, person_id: ^person.id, context: "login"), :count)

      for _ <- 1..3 do
        assert redirected_to(
                 post(conn, ~p"/people/register", %{"person" => %{"email" => person.email}})
               )
      end

      conn = post(conn, ~p"/people/register", %{"person" => %{"email" => person.email}})

      assert html_response(conn, 429) =~ "Register"
      refute html_response(conn, 429) =~ "already been taken"
      assert html_response(conn, 429) =~ ~s(value="#{person.email}")
      assert conn.assigns.flash["error"] =~ "Too many"

      assert Repo.aggregate(where(PersonToken, person_id: ^person.id, context: "login"), :count) ==
               before + 3
    end

    test "shares the per-email count with magic-link sign-in requests", %{conn: conn} do
      person = person_fixture()

      for _ <- 1..3 do
        post(conn, ~p"/people/signin", %{"person" => %{"email" => person.email}})
      end

      conn = post(conn, ~p"/people/register", %{"person" => %{"email" => person.email}})
      assert conn.status == 429
    end
  end
end
