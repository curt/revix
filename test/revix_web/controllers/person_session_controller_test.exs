defmodule RevixWeb.PersonSessionControllerTest do
  use RevixWeb.ConnCase, async: true

  import Ecto.Query

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

    test "confirming a person disconnects the live sockets of their expired sessions",
         %{conn: conn, unconfirmed_person: person} do
      other_token = People.generate_person_session_token(person)
      other_topic = "people_sessions:#{Base.url_encode64(other_token)}"
      RevixWeb.Endpoint.subscribe(other_topic)
      {token, _hashed_token} = generate_person_magic_link_token(person)

      post(conn, ~p"/people/signin", %{"person" => %{"token" => token}})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^other_topic}
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

  describe "POST /people/signin - rate limits" do
    @limited "Too many sign-in attempts. Please wait a few minutes and try again."

    defp sign_in(conn, params), do: post(conn, ~p"/people/signin", %{"person" => params})

    defp from_ip(conn, ip), do: %{conn | remote_ip: ip}

    test "blocks password attempts for an email after ten in fifteen minutes",
         %{conn: conn, person: person} do
      person = set_password(person)

      for _ <- 1..10 do
        assert sign_in(conn, %{"email" => person.email, "password" => "wrong"}).status == 200
      end

      conn = sign_in(conn, %{"email" => person.email, "password" => valid_person_password()})

      assert html_response(conn, 429) =~ ~s(id="login_form_password")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == @limited
      refute get_session(conn, :person_token)
    end

    test "counts the email limit across IP addresses", %{conn: conn, person: person} do
      for n <- 1..10 do
        sign_in(from_ip(conn, {127, 9, 9, n}), %{"email" => person.email, "password" => "wrong"})
      end

      limited =
        sign_in(from_ip(conn, {127, 9, 9, 99}), %{"email" => person.email, "password" => "x"})

      assert limited.status == 429
    end

    test "matches emails case-insensitively and ignores surrounding spaces",
         %{conn: conn, person: person} do
      for _ <- 1..10, do: sign_in(conn, %{"email" => person.email, "password" => "wrong"})

      shouted = "  " <> String.upcase(person.email) <> " "
      assert sign_in(conn, %{"email" => shouted, "password" => "wrong"}).status == 429
    end

    test "blocks password attempts from an IP after fifty in fifteen minutes", %{conn: conn} do
      for n <- 1..50 do
        assert sign_in(conn, %{"email" => "nobody#{n}@example.com", "password" => "x"}).status ==
                 200
      end

      assert sign_in(conn, %{"email" => "nobody51@example.com", "password" => "x"}).status == 429
    end

    test "does not reveal whether a limited email has an account", %{conn: conn} do
      for _ <- 1..10, do: sign_in(conn, %{"email" => "ghost@example.com", "password" => "x"})

      conn = sign_in(conn, %{"email" => "ghost@example.com", "password" => "x"})
      assert conn.status == 429
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == @limited
    end

    test "limits magic-link requests to three per email", %{conn: conn, person: person} do
      for _ <- 1..3 do
        conn = sign_in(conn, %{"email" => person.email})
        assert redirected_to(conn) == ~p"/people/signin"
      end

      conn = sign_in(conn, %{"email" => person.email})
      assert html_response(conn, 429)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == @limited

      assert Revix.Repo.aggregate(
               where(People.PersonToken, person_id: ^person.id, context: "login"),
               :count
             ) == 3
    end

    test "limits magic-link requests to ten per IP", %{conn: conn} do
      for n <- 1..10 do
        assert redirected_to(sign_in(conn, %{"email" => "someone#{n}@example.com"}))
      end

      assert sign_in(conn, %{"email" => "someone11@example.com"}).status == 429
    end

    test "keeps password and magic-link counts separate", %{conn: conn, person: person} do
      for _ <- 1..10, do: sign_in(conn, %{"email" => person.email, "password" => "wrong"})

      assert redirected_to(sign_in(conn, %{"email" => person.email})) == ~p"/people/signin"
    end

    test "counts clients behind the reverse proxy separately", %{conn: conn} do
      proxy = %{conn | remote_ip: {127, 0, 0, 1}}

      for n <- 1..11 do
        client = put_req_header(proxy, "x-forwarded-for", "203.0.113.#{n}")
        assert redirected_to(sign_in(client, %{"email" => "proxied#{n}@example.com"}))
      end
    end
  end
end
