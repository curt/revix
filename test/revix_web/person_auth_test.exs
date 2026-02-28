defmodule RevixWeb.PersonAuthTest do
  use RevixWeb.ConnCase, async: true

  alias Revix.People
  alias Revix.People.Scope
  alias RevixWeb.PersonAuth

  import Revix.PeopleFixtures

  @remember_me_cookie "_revix_web_person_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, RevixWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{person: %{person_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}
  end

  describe "log_in_person/3" do
    test "stores the person token in the session", %{conn: conn, person: person} do
      conn = PersonAuth.log_in_person(conn, person)
      assert token = get_session(conn, :person_token)
      assert redirected_to(conn) == ~p"/"
      assert People.get_person_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, person: person} do
      conn = conn |> put_session(:to_be_removed, "value") |> PersonAuth.log_in_person(person)
      refute get_session(conn, :to_be_removed)
    end

    test "keeps session when re-authenticating", %{conn: conn, person: person} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_person(person))
        |> put_session(:to_be_removed, "value")
        |> PersonAuth.log_in_person(person)

      assert get_session(conn, :to_be_removed)
    end

    test "clears session when person does not match when re-authenticating", %{
      conn: conn,
      person: person
    } do
      other_person = person_fixture()

      conn =
        conn
        |> assign(:current_scope, Scope.for_person(other_person))
        |> put_session(:to_be_removed, "value")
        |> PersonAuth.log_in_person(person)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, person: person} do
      conn = conn |> put_session(:person_return_to, "/hello") |> PersonAuth.log_in_person(person)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, person: person} do
      conn =
        conn |> fetch_cookies() |> PersonAuth.log_in_person(person, %{"remember_me" => "true"})

      assert get_session(conn, :person_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :person_remember_me) == true

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :person_token)
      assert max_age == @remember_me_cookie_max_age
    end

    test "writes a cookie if remember_me was set in previous session", %{
      conn: conn,
      person: person
    } do
      conn =
        conn |> fetch_cookies() |> PersonAuth.log_in_person(person, %{"remember_me" => "true"})

      assert get_session(conn, :person_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :person_remember_me) == true

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, RevixWeb.Endpoint.config(:secret_key_base))
        |> fetch_cookies()
        |> init_test_session(%{person_remember_me: true})

      # the conn is already logged in and has the remember_me cookie set,
      # now we sign in again and even without explicitly setting remember_me,
      # the cookie should be set again
      conn = conn |> PersonAuth.log_in_person(person, %{})
      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :person_token)
      assert max_age == @remember_me_cookie_max_age
      assert get_session(conn, :person_remember_me) == true
    end
  end

  describe "logout_person/1" do
    test "erases session and cookies", %{conn: conn, person: person} do
      person_token = People.generate_person_session_token(person)

      conn =
        conn
        |> put_session(:person_token, person_token)
        |> put_req_cookie(@remember_me_cookie, person_token)
        |> fetch_cookies()
        |> PersonAuth.log_out_person()

      refute get_session(conn, :person_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute People.get_person_by_session_token(person_token)
    end

    test "works even if person is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> PersonAuth.log_out_person()
      refute get_session(conn, :person_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_scope_for_person/2" do
    test "authenticates person from session", %{conn: conn, person: person} do
      person_token = People.generate_person_session_token(person)

      conn =
        conn
        |> put_session(:person_token, person_token)
        |> PersonAuth.fetch_current_scope_for_person([])

      assert conn.assigns.current_scope.person.id == person.id
      assert conn.assigns.current_scope.person.authenticated_at == person.authenticated_at
      assert get_session(conn, :person_token) == person_token
    end

    test "authenticates person from cookies", %{conn: conn, person: person} do
      logged_in_conn =
        conn |> fetch_cookies() |> PersonAuth.log_in_person(person, %{"remember_me" => "true"})

      person_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> PersonAuth.fetch_current_scope_for_person([])

      assert conn.assigns.current_scope.person.id == person.id
      assert conn.assigns.current_scope.person.authenticated_at == person.authenticated_at
      assert get_session(conn, :person_token) == person_token
      assert get_session(conn, :person_remember_me)
    end

    test "does not authenticate if data is missing", %{conn: conn, person: person} do
      _ = People.generate_person_session_token(person)
      conn = PersonAuth.fetch_current_scope_for_person(conn, [])
      refute get_session(conn, :person_token)
      refute conn.assigns.current_scope
    end

    test "reissues a new token after a few days and refreshes cookie", %{
      conn: conn,
      person: person
    } do
      logged_in_conn =
        conn |> fetch_cookies() |> PersonAuth.log_in_person(person, %{"remember_me" => "true"})

      token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      offset_person_token(token, -10, :day)
      {person, _} = People.get_person_by_session_token(token)

      conn =
        conn
        |> put_session(:person_token, token)
        |> put_session(:person_remember_me, true)
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> PersonAuth.fetch_current_scope_for_person([])

      assert conn.assigns.current_scope.person.id == person.id
      assert conn.assigns.current_scope.person.authenticated_at == person.authenticated_at
      assert new_token = get_session(conn, :person_token)
      assert new_token != token
      assert %{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert new_signed_token != signed_token
      assert max_age == @remember_me_cookie_max_age
    end
  end

  describe "require_sudo_mode/2" do
    test "allows people that have authenticated in the last 10 minutes", %{
      conn: conn,
      person: person
    } do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.require_sudo_mode([])

      refute conn.halted
      refute conn.status
    end

    test "redirects when authentication is too old", %{conn: conn, person: person} do
      eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)
      person = %{person | authenticated_at: eleven_minutes_ago}
      person_token = People.generate_person_session_token(person)
      {person, token_inserted_at} = People.get_person_by_session_token(person_token)
      assert DateTime.compare(token_inserted_at, person.authenticated_at) == :gt

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.require_sudo_mode([])

      assert redirected_to(conn) == ~p"/people/signin"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end
  end

  describe "redirect_if_person_is_authenticated/2" do
    setup %{conn: conn} do
      %{conn: PersonAuth.fetch_current_scope_for_person(conn, [])}
    end

    test "redirects if person is authenticated", %{conn: conn, person: person} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.redirect_if_person_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end

    test "does not redirect if person is not authenticated", %{conn: conn} do
      conn = PersonAuth.redirect_if_person_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_person/2" do
    setup %{conn: conn} do
      %{conn: PersonAuth.fetch_current_scope_for_person(conn, [])}
    end

    test "redirects if person is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> PersonAuth.require_authenticated_person([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/people/signin"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must sign in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> PersonAuth.require_authenticated_person([])

      assert halted_conn.halted
      assert get_session(halted_conn, :person_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> PersonAuth.require_authenticated_person([])

      assert halted_conn.halted
      assert get_session(halted_conn, :person_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> PersonAuth.require_authenticated_person([])

      assert halted_conn.halted
      refute get_session(halted_conn, :person_return_to)
    end

    test "does not redirect if person is authenticated", %{conn: conn, person: person} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.require_authenticated_person([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "require_role/2" do
    setup %{conn: conn} do
      %{conn: PersonAuth.fetch_current_scope_for_person(conn, [])}
    end

    test "allows person with matching role", %{conn: conn, person: person} do
      person = %{person | role: :owner}

      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.require_role(:owner)

      refute conn.halted
      refute conn.status
    end

    test "redirects person without matching role", %{conn: conn, person: person} do
      conn =
        conn
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_person(person))
        |> PersonAuth.require_role(:owner)

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You do not have permission to access this page."
    end

    test "redirects when no scope is assigned", %{conn: conn} do
      conn =
        conn
        |> fetch_flash()
        |> PersonAuth.require_role(:owner)

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end
  end
end
