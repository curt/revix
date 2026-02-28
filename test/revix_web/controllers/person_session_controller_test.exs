defmodule RevixWeb.PersonSessionControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures
  alias Revix.People

  setup do
    %{unconfirmed_person: unconfirmed_person_fixture(), person: person_fixture()}
  end

  describe "GET /people/signin" do
    test "renders login page", %{conn: conn} do
      conn = get(conn, ~p"/people/signin")
      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ ~p"/people/register"
      assert response =~ "Sign in with email"
    end

    test "renders login page with email filled in (sudo mode)", %{conn: conn, person: person} do
      html =
        conn
        |> log_in_person(person)
        |> get(~p"/people/signin")
        |> html_response(200)

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Sign in with email"

      assert html =~
               ~s(<input type="email" name="person[email]" id="login_form_magic_email" value="#{person.email}")
    end

    test "renders login page (email + password)", %{conn: conn} do
      conn = get(conn, ~p"/people/signin?mode=password")
      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ ~p"/people/register"
      assert response =~ "Sign in with email"
    end
  end

  describe "GET /people/signin/:token" do
    test "renders confirmation page for unconfirmed person", %{
      conn: conn,
      unconfirmed_person: person
    } do
      token =
        extract_person_token(fn url ->
          People.deliver_login_instructions(person, url)
        end)

      conn = get(conn, ~p"/people/signin/#{token}")
      assert html_response(conn, 200) =~ "Confirm and stay logged in"
    end

    test "renders login page for confirmed person", %{conn: conn, person: person} do
      token =
        extract_person_token(fn url ->
          People.deliver_login_instructions(person, url)
        end)

      conn = get(conn, ~p"/people/signin/#{token}")
      html = html_response(conn, 200)
      refute html =~ "Confirm my account"
      assert html =~ "Sign in"
    end

    test "raises error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/people/signin/invalid-token")
      assert redirected_to(conn) == ~p"/people/signin"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Magic link is invalid or it has expired."
    end
  end

  describe "POST /people/signin - email and password" do
    test "logs the person in", %{conn: conn, person: person} do
      person = set_password(person)

      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{"email" => person.email, "password" => valid_person_password()}
        })

      assert get_session(conn, :person_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ person.email
      assert response =~ ~p"/people/settings"
      assert response =~ ~p"/people/signout"
    end

    test "logs the person in with remember me", %{conn: conn, person: person} do
      person = set_password(person)

      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{
            "email" => person.email,
            "password" => valid_person_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_revix_web_person_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the person in with return to", %{conn: conn, person: person} do
      person = set_password(person)

      conn =
        conn
        |> init_test_session(person_return_to: "/foo/bar")
        |> post(~p"/people/signin", %{
          "person" => %{
            "email" => person.email,
            "password" => valid_person_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "emits error message with invalid credentials", %{conn: conn, person: person} do
      conn =
        post(conn, ~p"/people/signin?mode=password", %{
          "person" => %{"email" => person.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ "Invalid email or password"
    end
  end

  describe "POST /people/signin - magic link" do
    test "sends magic link email when person exists", %{conn: conn, person: person} do
      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{"email" => person.email}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Revix.Repo.get_by!(People.PersonToken, person_id: person.id).context == "login"
    end

    test "logs the person in", %{conn: conn, person: person} do
      {token, _hashed_token} = generate_person_magic_link_token(person)

      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{"token" => token}
        })

      assert get_session(conn, :person_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ person.email
      assert response =~ ~p"/people/settings"
      assert response =~ ~p"/people/signout"
    end

    test "confirms unconfirmed person", %{conn: conn, unconfirmed_person: person} do
      {token, _hashed_token} = generate_person_magic_link_token(person)
      refute person.confirmed_at

      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :person_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Person confirmed successfully."

      assert People.get_person!(person.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ person.email
      assert response =~ ~p"/people/settings"
      assert response =~ ~p"/people/signout"
    end

    test "emits error message when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/people/signin", %{
          "person" => %{"token" => "invalid"}
        })

      assert html_response(conn, 200) =~ "The link is invalid or it has expired."
    end
  end

  describe "DELETE /people/signout" do
    test "logs the person out", %{conn: conn, person: person} do
      conn = conn |> log_in_person(person) |> delete(~p"/people/signout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :person_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the person is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/people/signout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :person_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
