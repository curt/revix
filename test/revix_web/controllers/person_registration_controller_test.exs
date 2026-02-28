defmodule RevixWeb.PersonRegistrationControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures

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

      assert conn.assigns.flash["info"] =~
               ~r/An email was sent to .*, please access it to confirm your account/
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
end
