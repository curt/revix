defmodule RevixWeb.PingsLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures

  alias Revix.People

  setup do
    Req.Test.stub(:federation, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(202, "")
    end)

    :ok
  end

  describe "/pings" do
    test "redirects non-owner to home", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pings")
    end

    test "renders ping table for owner", %{conn: conn} do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      conn = log_in_person(conn, person)

      {:ok, _lv, html} = live(conn, ~p"/pings")

      assert html =~ "ActivityPub Pings"
      assert html =~ "Send Ping"
    end

    test "shows no pings message when empty", %{conn: conn} do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      conn = log_in_person(conn, person)

      {:ok, _lv, html} = live(conn, ~p"/pings")

      assert html =~ "No pings yet"
    end

    test "owner can send a ping", %{conn: conn} do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/pings")

      html =
        lv
        |> form("form", %{"target_uri" => "https://remote.example.com/users/alice"})
        |> render_submit()

      assert html =~ "Ping sent" or html =~ "Failed to send ping" or
               html =~ "remote.example.com"
    end

    test "redirects unauthenticated user", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/pings")
      assert path =~ "/people/signin"
    end
  end
end
